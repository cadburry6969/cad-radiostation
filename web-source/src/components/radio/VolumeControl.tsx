import { Volume2 } from 'lucide-react';

interface VolumeControlProps {
  volume: number;
  step: number;
  onChange: (volume: number) => void;
}

// Volume slider emitting a 0-100 value snapped to `step`.
function VolumeControl({ volume, step, onChange }: VolumeControlProps) {
  return (
    <div className="flex items-center gap-3 rounded-lg bg-white/5 px-4 py-3">
      <Volume2 size={18} className="text-primary" />
      <input
        type="range"
        min={0}
        max={100}
        step={step}
        value={volume}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-white/20 accent-red-600"
        aria-label="Radio volume"
      />
      <span className="w-10 text-right text-sm font-semibold tabular-nums text-white/80">
        {volume}%
      </span>
    </div>
  );
}

export default VolumeControl;
