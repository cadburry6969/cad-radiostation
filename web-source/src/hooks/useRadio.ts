import { useEffect, useRef, useState } from 'react';
import { useNuiEvent } from './useNuiEvent';
import { fetchNui } from '../utils/fetchNui';
import { resolveMediaSource } from '../utils/mediaSource';
import { embedPlayer } from '../utils/embedPlayer';

const ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
];

interface SignalPayload {
  signalType: 'offer' | 'answer' | 'ice';
  fromPeerId: string;
  sdp?: string;
  candidate?: RTCIceCandidateInit;
}

const clamp = (value: number) => Math.min(1, Math.max(0, value));

// The audio engine: one player for the stream, plus WebRTC peers for live voice.
export const useRadio = () => {
  const [isTransmitting, setIsTransmitting] = useState(false);
  const [isLive, setIsLive] = useState(false);

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const volumeRef = useRef(0.5);

  const localStreamRef = useRef<MediaStream | null>(null);
  const peersRef = useRef<Record<string, RTCPeerConnection>>({});
  const remoteAudiosRef = useRef<Record<string, HTMLAudioElement>>({});

  // Push-to-talk is off until the key is held, and must survive a late mic grant
  const transmitRef = useRef(false);

  const stopStream = () => {
    embedPlayer.stop();

    const audio = audioRef.current;
    if (!audio) return;
    audio.pause();
    audio.src = '';
    audio.load();
    audioRef.current = null;
  };

  const playStream = (url: string, volume?: number) => {
    stopStream();
    if (!url) return;

    if (volume !== undefined) volumeRef.current = clamp(volume);

    const source = resolveMediaSource(url);

    if (source.kind === 'embed' && source.embedId) {
      embedPlayer.play(source.embedId, volumeRef.current).catch(() => {
        fetchNui('audioError', { error: 'Failed to load stream' });
      });
      return;
    }

    const audio = new Audio(source.url);
    audio.crossOrigin = 'anonymous';
    audio.volume = volumeRef.current;

    audio.addEventListener('error', () => {
      fetchNui('audioError', { error: 'Failed to load stream' });
    });

    audio.play().catch((err: Error) => {
      fetchNui('audioError', { error: err.message });
    });

    audioRef.current = audio;
  };

  // One volume controls the stream, any embed, and incoming live voice
  const setVolume = (volume: number) => {
    volumeRef.current = clamp(volume);
    if (audioRef.current) audioRef.current.volume = volumeRef.current;
    embedPlayer.setVolume(volumeRef.current);
    Object.values(remoteAudiosRef.current).forEach((audio) => {
      audio.volume = volumeRef.current;
    });
  };

  const closePeer = (peerId: string) => {
    peersRef.current[peerId]?.close();
    delete peersRef.current[peerId];

    const audio = remoteAudiosRef.current[peerId];
    if (audio) {
      audio.pause();
      audio.srcObject = null;
      delete remoteAudiosRef.current[peerId];
    }
  };

  const closeAllPeers = () => {
    Object.keys(peersRef.current).forEach(closePeer);
  };

  // Mutes or unmutes the outgoing tracks without detaching them
  const applyTransmit = () => {
    localStreamRef.current?.getAudioTracks().forEach((track) => {
      track.enabled = transmitRef.current;
    });
  };

  const stopMicCapture = () => {
    closeAllPeers();
    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;
    transmitRef.current = false;
    setIsTransmitting(false);
  };

  const startMicCapture = async () => {
    try {
      localStreamRef.current = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          sampleRate: 48000,
        },
        video: false,
      });
      // getUserMedia hands back live tracks, so re-apply the armed state
      applyTransmit();
      fetchNui('micCaptured', { success: true });
    } catch (err) {
      const error = err as Error;
      fetchNui('micCaptured', { success: false, error: `${error.name}: ${error.message}` });
    }
  };

  const setTransmit = (enabled: boolean) => {
    transmitRef.current = enabled;
    applyTransmit();
    setIsTransmitting(enabled);
  };

  const makePeerConnection = (peerId: string) => {
    closePeer(peerId);
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });

    pc.onicecandidate = (event) => {
      if (!event.candidate) return;
      fetchNui('signal', {
        targetPeerId: peerId,
        type: 'ice',
        candidate: {
          candidate: event.candidate.candidate,
          sdpMid: event.candidate.sdpMid,
          sdpMLineIndex: event.candidate.sdpMLineIndex,
        },
      });
    };

    pc.ontrack = (event) => {
      let audio = remoteAudiosRef.current[peerId];
      if (!audio) {
        audio = new Audio();
        audio.autoplay = true;
        remoteAudiosRef.current[peerId] = audio;
      }
      audio.volume = volumeRef.current;
      audio.srcObject = event.streams[0];
      audio.play().catch(() => undefined);
      fetchNui('voiceConnected', { peerId });
    };

    pc.oniceconnectionstatechange = () => {
      if (pc.iceConnectionState === 'failed' || pc.iceConnectionState === 'disconnected') {
        closePeer(peerId);
      }
    };

    peersRef.current[peerId] = pc;
    return pc;
  };

  const createOfferFor = async (listenerId: string) => {
    const localStream = localStreamRef.current;
    if (!localStream) return;

    const pc = makePeerConnection(listenerId);
    localStream.getTracks().forEach((track) => pc.addTrack(track, localStream));

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    fetchNui('signal', { targetPeerId: listenerId, type: 'offer', sdp: offer.sdp });
  };

  const handleOffer = async (fromId: string, sdp: string) => {
    const pc = makePeerConnection(fromId);
    await pc.setRemoteDescription({ type: 'offer', sdp });
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    fetchNui('signal', { targetPeerId: fromId, type: 'answer', sdp: answer.sdp });
  };

  const handleAnswer = async (fromId: string, sdp: string) => {
    await peersRef.current[fromId]?.setRemoteDescription({ type: 'answer', sdp });
  };

  const handleIce = async (fromId: string, candidate: RTCIceCandidateInit) => {
    await peersRef.current[fromId]?.addIceCandidate(candidate);
  };

  useNuiEvent<{ url: string; volume?: number }>('playStream', (data) =>
    playStream(data.url, data.volume),
  );
  useNuiEvent('stopStream', stopStream);
  useNuiEvent<{ volume: number }>('setVolume', (data) => setVolume(data.volume));

  useNuiEvent('startMic', startMicCapture);
  useNuiEvent('stopMic', stopMicCapture);
  useNuiEvent<{ enabled: boolean }>('setTransmit', (data) => setTransmit(data.enabled));
  useNuiEvent<{ listenerId: string }>('createOffer', (data) => createOfferFor(data.listenerId));
  useNuiEvent<{ peerId: string }>('closePeer', (data) => closePeer(data.peerId));
  useNuiEvent('closeAll', stopMicCapture);
  useNuiEvent<{ enabled: boolean }>('setLive', (data) => setIsLive(data.enabled));

  useNuiEvent<SignalPayload>('signal', (data) => {
    if (data.signalType === 'offer' && data.sdp) handleOffer(data.fromPeerId, data.sdp);
    else if (data.signalType === 'answer' && data.sdp) handleAnswer(data.fromPeerId, data.sdp);
    else if (data.signalType === 'ice' && data.candidate) handleIce(data.fromPeerId, data.candidate);
  });

  useEffect(() => {
    return () => {
      stopStream();
      stopMicCapture();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { isTransmitting, isLive };
};
