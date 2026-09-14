# Radio Station

A radio resource with two separate screens:

- **Vehicle radio** is listen-only. You open it with the keybind (`F5` by default)
  while you are sitting in a vehicle. It lists every station, lets you tune, and
  lets you set the volume.
- **Station panel** is the control room for one single station. You open it from
  that station's broadcast area or from one of its map points, and you can use it
  while on foot. This is the only place you can start broadcasting.

Voice broadcasts work like a walkie-talkie. When you go live the mic opens muted,
and your voice is only sent out while you hold the push-to-talk key
(`ClientConfig.pttKey`, which is `ALT` by default).

---

## Layout

```
config/shared.lua     shared: debug flag, volume settings
config/client.lua     client only: keybinds, zone debug, editor command
config/server.lua     server only: stations, stream URLs, host jobs, ACE permissions
shared/types.lua      type annotations, no runtime code
bridge/               framework adapters (notify, player lookup)
modules/audio/        NUI audio and WebRTC bridge (client)
modules/radio/        playback state, tuning, the two screens
modules/station/      station cache and zones/targets (client), station store (server)
modules/editor/       in-game station editor (client)
web-source/           React UI source; "pnpm build" outputs to "web/"
```

### How config loads

Each config file returns a table. It gets pulled in with `lib.load` from the
matching bridge, which runs before every module:

```lua
Config = lib.load('config.shared')        -- both sides
ClientConfig = lib.load('config.client')  -- bridge/client.lua
ServerConfig = lib.load('config.server')  -- bridge/server.lua
```

Only `config/shared.lua` and `config/client.lua` are listed in `files{}`, so
`config/server.lua` is never sent to a client. That means the stream URLs,
`hostJobs` and the ACE permission names all stay on the server. Clients get a
trimmed station list (`ClientStation`) that leaves both of those out, and the
stream URL is only handed to a player the moment they tune in.

Config keys are camelCase (`Config.volumeStep`, `ClientConfig.pttKey`,
`ServerConfig.hostAcePermission`).

---

## The stations themselves

Stations live in the `stations` list inside `config/server.lua`. That list is
used to seed the store the first time the resource runs, and again whenever
someone hits "Reset to config defaults" in the editor. After that, edits made
in-game are what players actually see (unless you turn off
`ServerConfig.persistStations`).

Each station is made up of these fields:

| Field | What it is |
|-------|-----------|
| `id` | A short internal name, no spaces. Has to be unique. |
| `label` | The friendly name players see, like "Rock FM". |
| `frequency` | A unique whole number. It is how the radio dial and the internal routing tell stations apart. |
| `streamUrl` | The audio to play. Leave it empty for a talk-only station where the sound comes from someone broadcasting live. |
| `icon` | A FontAwesome solid icon name shown next to the station. |
| `description` | A one-line blurb shown in the menu. |
| `hostJobs` | The jobs allowed to broadcast here. Empty means only staff can. |
| `zones` | The box areas a host has to stand inside to go live. |
| `targets` | The map points a player can walk up to and interact with to open the panel. |

### What ships by default

Out of the box there are six stations. Five are music streams that just play,
and one is a live talk station.

| Station | Frequency | What it plays |
|---------|-----------|---------------|
| Rock FM | 8810 | Classic and modern rock |
| Pop Radio | 8820 | Pop hits |
| Weazel News | 8830 | Talk radio, broadcast live (no stream URL) |
| Jazz Radio | 8840 | Jazz |
| Chillhop Radio | 8850 | Chillhop |
| Hip Hop Radio | 8860 | Hip hop and chart hits |

The five music stations play automatically for anyone who tunes in, and they
have no zones, targets or host jobs set, so nobody broadcasts over them.

Weazel News is the example of a live station. It has no stream URL, so there is
nothing to hear until someone goes live. Only the `news`, `reporter` and
`police` jobs (plus staff) can broadcast on it, and they have to be standing in
the studio zone at the Weazel News building to do it. There is a target point
right there in the studio that opens the station panel.

---

## Permissions

| Action | Granted by |
|--------|-----------|
| Broadcast on a station | the `ServerConfig.hostAcePermission` ACE, a group listed in `ServerConfig.adminGroups`, or a job listed in that station's `hostJobs` |
| Create, edit or delete stations | the `ServerConfig.editorAcePermission` ACE, or a group listed in `ServerConfig.adminGroups` |

A host also has to be standing inside one of the station's zones. Walking out
stops an active broadcast on its own.

---

## In-game station editor

Run `/radiostations` (you can rename this in `ClientConfig.editorCommand`). It is
built on ox_lib context menus:

- **Create station**, or pick an existing one to edit.
- **Details**: id, label, frequency, stream URL, icon, description, host jobs.
- **Broadcast zones**: an interactive box builder. Walk around to position the
  box, use the arrow keys to resize length and width, `PAGE UP` and `PAGE DOWN`
  to set the height, `,` and `.` to rotate, `ENTER` to confirm, and `BACKSPACE`
  to cancel.
- **Target points**: aim with the camera and press `ENTER` to drop a point, then
  set its label, icon and radius.
- **Save station**: checked on the server (the id and frequency have to be
  unique) and then pushed to every client, which rebuilds its zones and targets
  right away.
- **Reset to config defaults**: throws away the in-game changes.

Changes are saved in the server KVP store. Set
`ServerConfig.persistStations = false` if you would rather have
`config/server.lua` win on every restart instead.

---

## Client Exports

`exports['cad-radiostation']:Export(...)`

| Export | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `GetCurrentStation` | `()` | `table\|nil` | The station the player is tuned to (`stationId`, `label`, `frequency`, `streamUrl`, `isBroadcasting`). |
| `IsListening` | `()` | `boolean` | Whether the player is tuned to any station. |
| `GetVolume` | `()` | `number` | Current volume, `0-100`. |
| `GetStations` | `()` | `ClientStation[]` | The trimmed station list this player is allowed to see. |
| `TuneToStation` | `(stationId: string)` | – | Tune by id. |
| `LeaveStation` | `()` | – | Stop playback and leave the station. |
| `OpenRadioMenu` | `()` | – | Open the vehicle radio. The player has to be in a vehicle. |
| `OpenStationPanel` | `(stationId: string)` | – | Open the control panel. The player needs broadcast permission on that station. |

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
| `GetStations` | `()` | `Station[]`, the live list, including stream URLs. |
| `GetStationById` | `(stationId: string)` | `Station\|nil` |
| `GetStationByFrequency` | `(frequency: number)` | `Station\|nil` |

`Station` fields: `id`, `label`, `frequency`, `streamUrl`, `icon`, `description`,
`hostJobs`, `zones`, `targets`.

---

## Server Callbacks (ox_lib)

Ask for these from the client with `lib.callback.await(name, false, ...)`.

| Callback | Args | Returns |
|----------|------|---------|
| `cad-radiostation:getStations` | – | `ClientStation[]` for the caller. |
| `cad-radiostation:canBroadcast` | `frequency: number` | `boolean` |
| `cad-radiostation:getBroadcastState` | `frequency: number` | `{ active, mode?, broadcasterSource? }` |
| `cad-radiostation:canEdit` | – | `boolean` |
| `cad-radiostation:getStationForEdit` | `stationId: string` | `Station\|nil`, the full record, editors only. |

---

## Net Events

### Client to Server

| Event | Args | Description |
|-------|------|-------------|
| `cad-radiostation:requestStations` | – | Ask for a fresh station list. |
| `cad-radiostation:tuneStation` | `stationId: string` | Tune the caller to a station. |
| `cad-radiostation:leaveStation` | – | Remove the caller as a listener. |
| `cad-radiostation:updateVolume` | `volume: number` | Save the caller's volume. |
| `cad-radiostation:startVoiceBroadcast` | `frequency: number` | Start a voice broadcast (permission is checked). |
| `cad-radiostation:startUrlBroadcast` | `frequency: number, url: string` | Push a stream URL to everyone on the frequency. |
| `cad-radiostation:stopBroadcast` | `frequency: number` | Stop the caller's broadcast. |
| `cad-radiostation:webrtc:signal` | `targetPeerId: number, signalData: table` | WebRTC signalling relay. |
| `cad-radiostation:editor:save` | `station: table, originalId: string\|nil` | Create or update a station. |
| `cad-radiostation:editor:delete` | `stationId: string` | Delete a station. |
| `cad-radiostation:editor:reset` | – | Restore the config defaults. |

### Server to Client

| Event | Payload | Description |
|-------|---------|-------------|
| `cad-radiostation:stations` | `ClientStation[]` | The station list changed; zones and targets get rebuilt. |
| `cad-radiostation:stationTuned` | `{ stationId, label, frequency, streamUrl, volume, isBroadcasting, broadcastMode }` | Tune confirmed, with playback info attached. |
| `cad-radiostation:stationLeft` | – | The player left, or was removed from, a station. |
| `cad-radiostation:broadcastStarted` | `{ frequency, mode }` | A voice broadcast started on the listener's frequency. |
| `cad-radiostation:voiceBroadcastApproved` | `{ frequency, listeners }` | Sent to the broadcaster: the mic is approved, create offers. |
| `cad-radiostation:broadcastStopped` | `{ frequency, streamUrl }` | The voice broadcast ended, so go back to the default stream. |
| `cad-radiostation:switchStream` | `{ frequency, streamUrl, isBroadcast }` | The active URL for a frequency changed. |
| `cad-radiostation:webrtc:signal` | `fromPeerId, signalData` | Incoming WebRTC signalling. |
| `cad-radiostation:webrtc:createOffer` | `listenerId: number` | The broadcaster should offer to a new listener. |
| `cad-radiostation:webrtc:closePeer` | `peerId: number` | Close a peer connection. |

---

## NUI reference (internal)

- **Lua to NUI**: `openRadio`, `openStation`, `closeMenu`, `updateRadioState`,
  `playStream`, `stopStream`, `setVolume`, `setLive`, `setTransmit`, `startMic`,
  `stopMic`, `createOffer`, `closePeer`, `closeAll`, `signal`.
- **NUI to Lua**: `closeMenu`, `tuneStation`, `leaveStation`, `setVolume`,
  `startVoiceBroadcast`, `startUrlBroadcast`, `stopBroadcast`, `micCaptured`,
  `signal`, `voiceConnected`, `audioError`.

The page is see-through over the game. Nothing in the UI can use
`backdrop-filter`: CEF composites it against an empty backdrop and paints the
result as a solid black rectangle.

### Broadcast sources

`utils/mediaSource.ts` sorts every URL (a station's `streamUrl`, plus anything
typed into the URL broadcast dialog) into one of two kinds: `direct` or `embed`.
Direct sources (`.mp3`, `.ogg`, Icecast/Shoutcast) play through an `Audio`
element. Embed sources are hosts that serve a player page instead of a plain
audio response, and those are handled by `utils/embedPlayer.ts`, which keeps one
off-screen provider iframe. The volume control drives whichever one is playing.

Rebuild after you change anything in `web-source/`:

```bash
cd web-source && pnpm install && pnpm build
```
