import { useState } from 'react';
import { AnimatePresence } from 'framer-motion';
import { Headphones, Link2, Mic, MicOff, PowerOff, TowerControl } from 'lucide-react';
import { useRadioStore } from '../../store/radio';
import { fetchNui } from '../../utils/fetchNui';
import Panel from '../ui/Panel';
import VolumeControl from './VolumeControl';
import UrlBroadcastDialog from './UrlBroadcastDialog';

interface StationPanelProps {
  onClose: () => void;
}

// Studio controls for one station, opened from its broadcast zone or target point.
function StationPanel({ onClose }: StationPanelProps) {
  const { station, state, config, broadcastState, setVolume } = useRadioStore();
  const [showUrlDialog, setShowUrlDialog] = useState(false);

  if (!station) return null;

  const isMonitoring = state.currentStationId === station.id;
  const isBroadcastingHere =
    state.isBroadcasting && state.broadcastFrequency === station.frequency;
  // Someone else already holds the frequency, so this player cannot take it
  const frequencyBusy = broadcastState.active && !isBroadcastingHere;

  const handleVolume = (volume: number) => {
    setVolume(volume);
    fetchNui('setVolume', { volume });
  };

  return (
    <Panel
      title={station.label}
      subtitle={`${station.frequency} MHz · Studio controls`}
      icon={<TowerControl size={20} />}
      footer={
        isBroadcastingHere && state.broadcastMode === 'voice'
          ? `Hold ${config.pttKeyLabel} to talk · ESC to close`
          : 'Press ESC to close'
      }
      onClose={onClose}
    >
      <div className="relative flex flex-col gap-3">
        {isBroadcastingHere ? (
          <div className="flex items-center gap-2 rounded-lg border border-red-500/40 bg-red-600/15 px-4 py-3 text-sm font-semibold text-red-300">
            <span className="h-2 w-2 animate-pulse rounded-full bg-red-500" />
            On air · {state.broadcastMode === 'voice' ? 'Voice' : 'URL'} broadcast
          </div>
        ) : frequencyBusy ? (
          <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-300">
            Another host is broadcasting on this frequency
          </div>
        ) : (
          <div className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-sm text-white/60">
            {station.description || 'Ready to broadcast'}
          </div>
        )}

        <div className="flex flex-col gap-2 border-t border-white/10 pt-3">
          {isBroadcastingHere ? (
            <button
              onClick={() => fetchNui('stopBroadcast', { frequency: station.frequency })}
              className="flex items-center justify-center gap-2 rounded-lg bg-red-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-red-500"
            >
              <MicOff size={16} /> End Broadcast
            </button>
          ) : (
            <>
              <button
                onClick={() => fetchNui('startVoiceBroadcast', { frequency: station.frequency })}
                disabled={frequencyBusy}
                className="flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
              >
                <Mic size={16} /> Go Live (Voice)
              </button>
              <button
                onClick={() => setShowUrlDialog(true)}
                disabled={frequencyBusy}
                className="flex items-center justify-center gap-2 rounded-lg bg-amber-500 px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:opacity-40"
              >
                <Link2 size={16} /> Broadcast a Link
              </button>
            </>
          )}
        </div>

        <div className="flex flex-col gap-2 border-t border-white/10 pt-3">
          {isMonitoring ? (
            <button
              onClick={() => fetchNui('leaveStation')}
              className="flex items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white/80 transition hover:bg-white/10"
            >
              <PowerOff size={16} /> Stop Monitoring
            </button>
          ) : (
            <button
              onClick={() => fetchNui('tuneStation', { stationId: station.id })}
              className="flex items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white/80 transition hover:bg-white/10"
            >
              <Headphones size={16} /> Monitor Output
            </button>
          )}

          <VolumeControl volume={state.volume} step={config.volumeStep} onChange={handleVolume} />
        </div>

        <AnimatePresence>
          {showUrlDialog && (
            <UrlBroadcastDialog
              onCancel={() => setShowUrlDialog(false)}
              onSubmit={(url) => {
                setShowUrlDialog(false);
                fetchNui('startUrlBroadcast', { frequency: station.frequency, url });
              }}
            />
          )}
        </AnimatePresence>
      </div>
    </Panel>
  );
}

export default StationPanel;
