import { create } from 'zustand';
import type {
  BroadcastState,
  OpenRadioPayload,
  OpenStationPayload,
  RadioConfig,
  RadioState,
  Station,
} from '../types/radio';

/** Which interface is on screen. The two are mutually exclusive. */
export type RadioView = 'radio' | 'station' | null;

const DEFAULT_CONFIG: RadioConfig = {
  volumeStep: 10,
  defaultVolume: 50,
  pttKeyLabel: 'ALT',
};

const DEFAULT_STATE: RadioState = {
  currentStationId: null,
  volume: 50,
  isBroadcasting: false,
  broadcastMode: null,
  broadcastFrequency: null,
};

interface RadioStore {
  view: RadioView;
  config: RadioConfig;
  state: RadioState;
  /** Stations listed by the vehicle radio. */
  stations: Station[];
  /** The single station the broadcast panel operates. */
  station: Station | null;
  /** Whether someone already holds the panel station's frequency. */
  broadcastState: BroadcastState;

  /** Show the listen-only vehicle radio. */
  openRadio: (payload: OpenRadioPayload) => void;
  /** Show the broadcast panel for one station. */
  openStation: (payload: OpenStationPayload) => void;
  /** Hide whichever view is open. */
  close: () => void;
  /** Replace the live state (from `updateRadioState`). */
  setState: (state: RadioState) => void;
  /** Optimistically update the volume; Lua remains the source of truth. */
  setVolume: (volume: number) => void;
}

export const useRadioStore = create<RadioStore>((set) => ({
  view: null,
  config: DEFAULT_CONFIG,
  state: DEFAULT_STATE,
  stations: [],
  station: null,
  broadcastState: { active: false },

  openRadio: (payload) =>
    set({
      view: 'radio',
      stations: payload.stations,
      state: payload.state,
      config: payload.config,
      station: null,
    }),

  openStation: (payload) =>
    set({
      view: 'station',
      station: payload.station,
      state: payload.state,
      config: payload.config,
      broadcastState: payload.broadcastState ?? { active: false },
    }),

  close: () => set({ view: null, station: null }),

  setState: (state) => set({ state }),

  setVolume: (volume) => set((prev) => ({ state: { ...prev.state, volume } })),
}));
