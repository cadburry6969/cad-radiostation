# Radio Station

A radio resource with two separate interfaces:

- **Vehicle radio** — listen-only. Opened with the keybind (`F5` by default) while
  seated in a vehicle. Lists every station, tunes, sets volume.
- **Station panel** — the studio control surface for a *single* station. Opened
  from that station's broadcast zone or one of its target points, and usable
  **on foot**. This is the only place broadcasting can be started.

Voice broadcasts are push-to-talk: going live opens the mic **muted**, and audio
is only transmitted while `ClientConfig.pttKey` (`ALT` by default) is held.

---

## Layout

```
config/shared.lua     shared — debug flag, volume settings
config/client.lua     client only — keybinds, zone debug, editor command
config/server.lua     server only — stations, stream URLs, host jobs, ACE permissions
shared/types.lua      type annotations, no runtime code
bridge/               framework adapters (notify, player lookup)
modules/audio/        NUI audio + WebRTC bridge (client)
modules/radio/        playback state, tuning, the two interfaces
modules/station/      station cache + zones/targets (client), station store (server)
modules/editor/       in-game station editor (client)
web-source/           React UI source; `pnpm build` outputs to `web/`
```

### Config loading

Each config file `return`s a table and is pulled in with `lib.load` from the
matching bridge, which runs before every module:

```lua
Config = lib.load('config.shared')        -- both sides
ClientConfig = lib.load('config.client')  -- bridge/client.lua
ServerConfig = lib.load('config.server')  -- bridge/server.lua
```

Only `config/shared.lua` and `config/client.lua` are listed in `files{}`, so
`config/server.lua` is never downloaded by a client. Stream URLs, `hostJobs` and
the ACE permission names therefore stay server-side; clients receive a sanitised
station list (`ClientStation`) that omits both fields, and the stream URL is only
delivered to a player at the moment they tune in.

Config keys are camelCase (`Config.volumeStep`, `ClientConfig.pttKey`,
`ServerConfig.hostAcePermission`).

---

## Permissions

| Action | Granted by |
|--------|-----------|
| Broadcast on a station | `ServerConfig.hostAcePermission` ACE, a group in `ServerConfig.adminGroups`, or a job listed in that station's `hostJobs` |
| Create/edit/delete stations | `ServerConfig.editorAcePermission` ACE, or a group in `ServerConfig.adminGroups` |

A host must also be **standing inside one of the station's zones** — walking out
stops an active broadcast automatically.

---

## In-game station editor

Run `/radiostations` (configurable via `ClientConfig.editorCommand`). Built on
ox_lib context menus:

- **Create station** / pick an existing one to edit
- **Details** — id, label, frequency, stream URL, icon, description, host jobs
- **Broadcast zones** — interactive box builder. Walk to position the box, arrow
  keys resize length/width, `PAGE UP`/`PAGE DOWN` set height, `,`/`.` rotate,
  `ENTER` confirms, `BACKSPACE` cancels.
- **Target points** — aim with the camera and press `ENTER` to place, then set
  the label, icon and radius.
- **Save station** — validated server-side (unique id and frequency) and pushed
  to every client, which rebuilds its zones and targets immediately.
- **Reset to config defaults** — discards in-game changes.

Changes persist through the server KVP store. Set
`ServerConfig.persistStations = false` to make `config/server.lua` authoritative
on every restart instead.

---

## Client Exports

`exports['cad-radiostation']:Export(...)`

| Export | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `GetCurrentStation` | `()` | `table\|nil` | Station the player is tuned to (`stationId`, `label`, `frequency`, `streamUrl`, `isBroadcasting`). |
| `IsListening` | `()` | `boolean` | Whether the player is tuned to any station. |
| `GetVolume` | `()` | `number` | Current volume, `0–100`. |
| `GetStations` | `()` | `ClientStation[]` | The sanitised station list this player can see. |
| `TuneToStation` | `(stationId: string)` | – | Tune by id. |
| `LeaveStation` | `()` | – | Stop playback and leave the station. |
| `OpenRadioMenu` | `()` | – | Open the vehicle radio. Requires being in a vehicle. |
| `OpenStationPanel` | `(stationId: string)` | – | Open the studio panel. Requires broadcast permission on that station. |

```lua
local station = exports['cad-radiostation']:GetCurrentStation()
if station then
    print('Listening to', station.label, 'on', station.frequency)
end
```

---

## Server Exports

| Export | Signature | Returns |
|--------|-----------|---------|
| `GetStations` | `()` | `Station[]` — the live list, including stream URLs. |
| `GetStationById` | `(stationId: string)` | `Station\|nil` |
| `GetStationByFrequency` | `(frequency: number)` | `Station\|nil` |

`Station` fields: `id`, `label`, `frequency`, `streamUrl`, `icon`, `description`,
`hostJobs`, `zones`, `targets`.

---

## Server Callbacks (ox_lib)

Request from the client with `lib.callback.await(name, false, ...)`.

| Callback | Args | Returns |
|----------|------|---------|
| `cad-radiostation:getStations` | – | `ClientStation[]` for the caller. |
| `cad-radiostation:canBroadcast` | `frequency: number` | `boolean` |
| `cad-radiostation:getBroadcastState` | `frequency: number` | `{ active, mode?, broadcasterSource? }` |
| `cad-radiostation:canEdit` | – | `boolean` |
| `cad-radiostation:getStationForEdit` | `stationId: string` | `Station\|nil` — full record, editors only. |

---

## Net Events

### Client → Server

| Event | Args | Description |
|-------|------|-------------|
| `cad-radiostation:requestStations` | – | Ask for a fresh station list. |
| `cad-radiostation:tuneStation` | `stationId: string` | Tune the caller to a station. |
| `cad-radiostation:leaveStation` | – | Remove the caller as a listener. |
| `cad-radiostation:updateVolume` | `volume: number` | Persist the caller's volume. |
| `cad-radiostation:startVoiceBroadcast` | `frequency: number` | Begin a voice broadcast (permission-checked). |
| `cad-radiostation:startUrlBroadcast` | `frequency: number, url: string` | Push a stream URL to everyone on the frequency. |
| `cad-radiostation:stopBroadcast` | `frequency: number` | Stop the caller's broadcast. |
| `cad-radiostation:webrtc:signal` | `targetPeerId: number, signalData: table` | WebRTC signalling relay. |
| `cad-radiostation:editor:save` | `station: table, originalId: string\|nil` | Create or update a station. |
| `cad-radiostation:editor:delete` | `stationId: string` | Delete a station. |
| `cad-radiostation:editor:reset` | – | Restore the config defaults. |

### Server → Client

| Event | Payload | Description |
|-------|---------|-------------|
| `cad-radiostation:stations` | `ClientStation[]` | The station list changed; zones and targets are rebuilt. |
| `cad-radiostation:stationTuned` | `{ stationId, label, frequency, streamUrl, volume, isBroadcasting, broadcastMode }` | Tune confirmed, playback info attached. |
| `cad-radiostation:stationLeft` | – | The player left, or was removed from, a station. |
| `cad-radiostation:broadcastStarted` | `{ frequency, mode }` | A voice broadcast started on the listener's frequency. |
| `cad-radiostation:voiceBroadcastApproved` | `{ frequency, listeners }` | Sent to the broadcaster; mic approved, create offers. |
| `cad-radiostation:broadcastStopped` | `{ frequency, streamUrl }` | Voice broadcast ended, resume the default stream. |
| `cad-radiostation:switchStream` | `{ frequency, streamUrl, isBroadcast }` | The active URL for a frequency changed. |
| `cad-radiostation:webrtc:signal` | `fromPeerId, signalData` | Incoming WebRTC signalling. |
| `cad-radiostation:webrtc:createOffer` | `listenerId: number` | Broadcaster should offer to a new listener. |
| `cad-radiostation:webrtc:closePeer` | `peerId: number` | Close a peer connection. |

---

## NUI reference (internal)

- **Lua → NUI**: `openRadio`, `openStation`, `closeMenu`, `updateRadioState`,
  `playStream`, `stopStream`, `setVolume`, `setLive`, `setTransmit`, `startMic`,
  `stopMic`, `createOffer`, `closePeer`, `closeAll`, `signal`.
- **NUI → Lua**: `closeMenu`, `tuneStation`, `leaveStation`, `setVolume`,
  `startVoiceBroadcast`, `startUrlBroadcast`, `stopBroadcast`, `micCaptured`,
  `signal`, `voiceConnected`, `audioError`.

The page is transparent over the game. Nothing in the UI may use
`backdrop-filter`: CEF composites it against an empty backdrop and paints the
result as an opaque black rectangle.

### Broadcast sources

`utils/mediaSource.ts` classifies every URL — a station's `streamUrl` and
anything entered in the URL broadcast dialog — as either `direct` or `embed`.
Direct sources (`.mp3`, `.ogg`, Icecast/Shoutcast) play through an `Audio`
element. Embed sources are hosts that serve a player page instead of a playable
audio response; those are driven by `utils/embedPlayer.ts`, which keeps a single
off-screen provider iframe. The volume control drives whichever one is active.

Rebuild after changing `web-source/`:

```bash
cd web-source && pnpm install && pnpm build
```
