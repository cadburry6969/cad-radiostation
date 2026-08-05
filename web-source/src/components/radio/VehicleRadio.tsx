import { PowerOff, Radio } from 'lucide-react';
import { useRadioStore } from '../../store/radio';
import { fetchNui } from '../../utils/fetchNui';
import Panel from '../ui/Panel';
import StationList from './StationList';
import VolumeControl from './VolumeControl';

interface VehicleRadioProps {
  onClose: () => void;
}

// The in-vehicle interface, listen only. Broadcasting lives in the station panel.
function VehicleRadio({ onClose }: VehicleRadioProps) {
  const { stations, state, config, setVolume } = useRadioStore();

  const handleVolume = (volume: number) => {
    setVolume(volume);
    fetchNui('setVolume', { volume });
  };

  return (
    <Panel title="Vehicle Radio" icon={<Radio size={20} />} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <StationList
          stations={stations}
          currentStationId={state.currentStationId}
          onSelect={(stationId) => fetchNui('tuneStation', { stationId })}
        />

        <VolumeControl volume={state.volume} step={config.volumeStep} onChange={handleVolume} />

        {state.currentStationId && (
          <button
            onClick={() => fetchNui('leaveStation')}
            className="flex items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white/80 transition hover:bg-white/10"
          >
            <PowerOff size={16} /> Turn Off
          </button>
        )}
      </div>
    </Panel>
  );
}

export default VehicleRadio;
