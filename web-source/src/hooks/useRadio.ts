import { useEffect, useRef, useState } from 'react';
import { useNuiEvent } from './useNuiEvent';
import { fetchNui } from '../utils/fetchNui';

const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
];

export const useRadio = () => {
  const [isTransmitting, setIsTransmitting] = useState(false);
  const [isLive, setIsLive] = useState(false);

  // Audio Stream State
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const streamVolumeRef = useRef(0.5);

  // WebRTC State
  const localStreamRef = useRef<MediaStream | null>(null);
  const peerConnectionsRef = useRef<Record<string, RTCPeerConnection>>({});
  const remoteAudiosRef = useRef<Record<string, HTMLAudioElement>>({});
  const isBroadcasterRef = useRef(false);
  const voiceVolumeRef = useRef(1.0);

  const clamp = (v: number) => Math.min(1.0, Math.max(0.0, v));

  // --- AUDIO STREAM LOGIC ---

  const stopStream = () => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.src = '';
      audioRef.current.load();
      audioRef.current = null;
    }
  };

  const playStream = (url: string, volume?: number) => {
    stopStream();
    if (!url || url === '') return;

    const audio = new Audio(url);
    audio.volume = clamp(volume !== undefined ? volume : streamVolumeRef.current);
    audio.crossOrigin = 'anonymous';

    audio.addEventListener('error', (e) => {
      const error = (e.target as any).error;
      console.error('[radio] Stream error:', error);
      fetchNui('audioError', { error: 'Failed to load stream' });
    });

    audio.play().then(() => {
      console.log('[radio] Stream playing:', url);
    }).catch((err) => {
      console.warn('[radio] Stream play failed:', err.message);
      fetchNui('audioError', { error: err.message });
    });

    audioRef.current = audio;
  };

  const setStreamVolume = (vol: number) => {
    streamVolumeRef.current = clamp(vol);
    if (audioRef.current) {
      audioRef.current.volume = streamVolumeRef.current;
    }
  };

  // --- WEBRTC LOGIC ---

  const closePeer = (peerId: string) => {
    const pc = peerConnectionsRef.current[peerId];
    if (pc) {
      pc.close();
      delete peerConnectionsRef.current[peerId];
    }
    const audio = remoteAudiosRef.current[peerId];
    if (audio) {
      audio.pause();
      audio.srcObject = null;
      delete remoteAudiosRef.current[peerId];
    }
  };

  const closeAllPeers = () => {
    Object.keys(peerConnectionsRef.current).forEach(closePeer);
    stopMicCapture();
  };

  const stopMicCapture = () => {
    Object.keys(peerConnectionsRef.current).forEach(closePeer);
    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach((t: any) => t.stop());
      localStreamRef.current = null;
    }
    isBroadcasterRef.current = false;
    setIsTransmitting(false);
    console.log('[radio] Mic released, broadcast stopped');
  };

  const startMicCapture = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          sampleRate: 48000,
        },
        video: false,
      });
      localStreamRef.current = stream;
      isBroadcasterRef.current = true;
      console.log('[radio] Mic captured successfully');
      fetchNui('micCaptured', { success: true });
    } catch (err: any) {
      console.error('[radio] getUserMedia failed:', err.name, err.message);
      fetchNui('micCaptured', { success: false, error: `${err.name}: ${err.message}` });
    }
  };

  const makePeerConnection = (peerId: string) => {
    if (peerConnectionsRef.current[peerId]) closePeer(peerId);

    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });

    pc.onicecandidate = (ev) => {
      if (ev.candidate) {
        fetchNui('signal', {
          targetPeerId: peerId,
          type: 'ice',
          candidate: {
            candidate: ev.candidate.candidate,
            sdpMid: ev.candidate.sdpMid,
            sdpMLineIndex: ev.candidate.sdpMLineIndex,
          },
        });
      }
    };

    pc.ontrack = (ev) => {
      console.log('[radio] Got remote audio from', peerId);
      let audio = remoteAudiosRef.current[peerId];
      if (!audio) {
        audio = new Audio();
        audio.autoplay = true;
        audio.volume = clamp(voiceVolumeRef.current);
        remoteAudiosRef.current[peerId] = audio;
      }
      audio.srcObject = ev.streams[0];
      audio.play().catch((e: any) => {
        console.warn('[radio] Remote audio play error:', e.message);
      });
      fetchNui('voiceConnected', { peerId });
    };

    pc.oniceconnectionstatechange = () => {
      console.log('[radio] ICE state', peerId, ':', pc.iceConnectionState);
      if (pc.iceConnectionState === 'failed' || pc.iceConnectionState === 'disconnected') {
        closePeer(peerId);
      }
    };

    peerConnectionsRef.current[peerId] = pc;
    return pc;
  };

  const createOfferFor = async (listenerId: string) => {
    if (!localStreamRef.current) {
      console.warn('[radio] No localStream, cannot create offer');
      return;
    }
    const pc = makePeerConnection(listenerId);
    localStreamRef.current.getTracks().forEach((track: any) => {
      pc.addTrack(track, localStreamRef.current!);
    });

    try {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      fetchNui('signal', {
        targetPeerId: listenerId,
        type: 'offer',
        sdp: offer.sdp,
      });
      console.log('[radio] Sent offer to', listenerId);
    } catch (err) {
      console.error('[radio] createOffer error:', err);
    }
  };

  const handleOffer = async (fromId: string, sdp: string) => {
    const pc = makePeerConnection(fromId);
    try {
      await pc.setRemoteDescription(new RTCSessionDescription({ type: 'offer', sdp }));
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      fetchNui('signal', {
        targetPeerId: fromId,
        type: 'answer',
        sdp: answer.sdp,
      });
      console.log('[radio] Sent answer to', fromId);
    } catch (err) {
      console.error('[radio] handleOffer error:', err);
    }
  };

  const handleAnswer = async (fromId: string, sdp: string) => {
    const pc = peerConnectionsRef.current[fromId];
    if (!pc) return;
    try {
      await pc.setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp }));
      console.log('[radio] Set answer from', fromId);
    } catch (err) {
      console.error('[radio] handleAnswer error:', err);
    }
  };

  const handleIce = async (fromId: string, candidate: any) => {
    const pc = peerConnectionsRef.current[fromId];
    if (!pc) return;
    try {
      await pc.addIceCandidate(new RTCIceCandidate(candidate));
    } catch (err) {
      console.error('[radio] addIceCandidate error:', err);
    }
  };

  const setVoiceVolume = (vol: number) => {
    voiceVolumeRef.current = clamp(vol);
    Object.values(remoteAudiosRef.current).forEach((audio: any) => {
      audio.volume = voiceVolumeRef.current;
    });
  };

  const setTransmit = (enabled: boolean) => {
    if (localStreamRef.current) {
      localStreamRef.current.getAudioTracks().forEach((track: any) => {
        track.enabled = enabled;
      });
      console.log('[radio] Transmit:', enabled ? 'ON' : 'OFF');
    }
    setIsTransmitting(enabled);
  };

  // --- NUI EVENT HANDLERS ---

  useNuiEvent<{ url: string; volume?: number }>('playStream', (data) => playStream(data.url, data.volume));
  useNuiEvent('stopStream', stopStream);
  useNuiEvent<{ volume: number }>('setVolume', (data) => setStreamVolume(data.volume));

  useNuiEvent('startMic', startMicCapture);
  useNuiEvent('stopMic', stopMicCapture);
  useNuiEvent<{ enabled: boolean }>('setTransmit', (data) => setTransmit(data.enabled));
  useNuiEvent<{ listenerId: string }>('createOffer', (data) => createOfferFor(data.listenerId));

  useNuiEvent<{ signalType: string; fromPeerId: string; sdp: string; candidate: any }>('signal', (data) => {
    if (data.signalType === 'offer') handleOffer(data.fromPeerId, data.sdp);
    else if (data.signalType === 'answer') handleAnswer(data.fromPeerId, data.sdp);
    else if (data.signalType === 'ice') handleIce(data.fromPeerId, data.candidate);
  });

  useNuiEvent<{ peerId: string }>('closePeer', (data) => closePeer(data.peerId));
  useNuiEvent('closeAll', closeAllPeers);
  useNuiEvent<{ enabled: boolean }>('setLive', (data) => setIsLive(data.enabled));
  useNuiEvent<{ volume: number }>('setVoiceVolume', (data) => setVoiceVolume(data.volume));

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopStream();
      closeAllPeers();
    };
  }, []);

  return { isTransmitting, isLive };
};
