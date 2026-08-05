--- A box zone a host must stand inside to broadcast on a station.
---@class StationZone
---@field coords vector3 Centre of the box
---@field size vector3 Box dimensions (x, y, z)
---@field heading number Rotation around the Z axis, in degrees

--- An interaction point that opens the station interface.
---@class StationTarget
---@field coords vector3
---@field radius number
---@field label string Text shown on the target eye
---@field icon string FontAwesome class, e.g. 'fa-solid fa-tower-broadcast'

--- Full station record. Server-side only: it carries the stream URL and host jobs.
---@class Station
---@field id string Unique identifier
---@field label string Display name
---@field frequency number Unique routing frequency
---@field streamUrl string Direct audio stream URL, may be empty for talk stations
---@field icon string FontAwesome solid icon name
---@field description string
---@field hostJobs string[] Jobs permitted to broadcast
---@field zones StationZone[]
---@field targets StationTarget[]

--- Station record mirrored to clients. Deliberately omits `streamUrl` and `hostJobs`;
--- the stream URL is only sent to a player at the moment they tune in.
---@class ClientStation
---@field id string
---@field label string
---@field frequency number
---@field icon string
---@field description string
---@field zones StationZone[]
---@field targets StationTarget[]
---@field canBroadcast boolean Whether this player may broadcast on the station

---@alias BroadcastMode 'voice' | 'url'

--- Live radio state mirrored to the NUI.
---@class RadioState
---@field currentStationId string|nil
---@field volume number 0-100
---@field isBroadcasting boolean
---@field broadcastMode BroadcastMode|nil
---@field broadcastFrequency number|nil

--- Who, if anyone, currently holds a frequency.
---@class BroadcastState
---@field active boolean
---@field mode BroadcastMode|nil
---@field broadcasterSource number|nil

--- Static values forwarded to the NUI on open.
---@class NuiConfig
---@field volumeStep number
---@field defaultVolume number
---@field pttKeyLabel string
