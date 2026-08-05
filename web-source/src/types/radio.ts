// Payload shapes sent by modules/radio/client.lua. Keep in sync with shared/types.lua.

/** A station as the client is allowed to see it. Never carries the stream URL. */
export interface Station {
  id: string;
  label: string;
  frequency: number;
  icon: string;
  description: string;
  /** Whether this player may broadcast on the station. */
  canBroadcast: boolean;
}

/** Static config values forwarded from Lua on open. */
export interface RadioConfig {
  volumeStep: number;
  defaultVolume: number;
  pttKeyLabel: string;
}

export type BroadcastMode = 'voice' | 'url';

/** Live radio state mirrored to the UI. */
export interface RadioState {
  currentStationId: string | null;
  volume: number;
  isBroadcasting: boolean;
  broadcastMode: BroadcastMode | null;
  broadcastFrequency: number | null;
}

/** Who, if anyone, currently holds a frequency. */
export interface BroadcastState {
  active: boolean;
  mode?: BroadcastMode;
  broadcasterSource?: number;
}

/** Payload for the `openRadio` message: the listen-only vehicle interface. */
export interface OpenRadioPayload {
  stations: Station[];
  state: RadioState;
  config: RadioConfig;
}

/** Payload for the `openStation` message: the broadcast interface. */
export interface OpenStationPayload {
  station: Station;
  state: RadioState;
  config: RadioConfig;
  broadcastState: BroadcastState;
}

/** Payload for the `updateRadioState` message. */
export interface UpdateStatePayload {
  state: RadioState;
}
