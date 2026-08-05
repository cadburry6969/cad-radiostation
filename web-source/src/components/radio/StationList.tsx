import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import type { IconName } from '@fortawesome/fontawesome-svg-core';
import type { Station } from '../../types/radio';

interface StationListProps {
  stations: Station[];
  currentStationId: string | null;
  onSelect: (stationId: string) => void;
}

/** Scrollable station picker. Selecting a row tunes straight to it. */
function StationList({ stations, currentStationId, onSelect }: StationListProps) {
  if (stations.length === 0) {
    return (
      <p className="rounded-lg border border-white/10 bg-white/5 px-4 py-6 text-center text-sm text-white/50">
        No stations available
      </p>
    );
  }

  return (
    <ul className="custom-scrollbar flex max-h-[46vh] flex-col gap-2 overflow-y-auto pr-1">
      {stations.map((station) => {
        const isActive = station.id === currentStationId;
        return (
          <li key={station.id}>
            <button
              onClick={() => onSelect(station.id)}
              className={`flex w-full items-center gap-3 rounded-lg border px-4 py-3 text-left transition ${
                isActive
                  ? 'border-primary/60 bg-primary/10'
                  : 'border-white/10 bg-white/5 hover:border-white/20 hover:bg-white/10'
              }`}
            >
              <span
                className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-md ${
                  isActive ? 'bg-primary/20 text-primary' : 'bg-black/30 text-white/70'
                }`}
              >
                <FontAwesomeIcon icon={station.icon as IconName} />
              </span>

              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate font-semibold text-white">{station.label}</span>
                  {isActive && (
                    <span className="rounded bg-green-500/20 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-green-400">
                      Playing
                    </span>
                  )}
                </div>
                <p className="truncate text-xs text-white/50">{station.description}</p>
              </div>

              <span className="shrink-0 text-xs tabular-nums text-white/30">{station.frequency}</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export default StationList;
