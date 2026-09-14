local KVP_KEY = 'cad-radiostation:stations'

--- Converts a vector3 or {x,y,z} table into a plain table safe for JSON storage.
---@param value any
---@return { x: number, y: number, z: number }|nil
local function toCoordsTable(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

--- Copies and validates a zone definition.
---@param raw any
---@return StationZone|nil
local function normalizeZone(raw)
    if type(raw) ~= 'table' then return nil end
    local coords = toCoordsTable(raw.coords)
    if not coords then return nil end
    local size = toCoordsTable(raw.size) or { x = 4.0, y = 4.0, z = 3.0 }
    return { coords = coords, size = size, heading = tonumber(raw.heading) or 0.0 }
end

--- Copies and validates a target definition.
---@param raw any
---@return StationTarget|nil
local function normalizeTarget(raw)
    if type(raw) ~= 'table' then return nil end
    local coords = toCoordsTable(raw.coords)
    if not coords then return nil end
    return {
        coords = coords,
        radius = tonumber(raw.radius) or 1.0,
        label  = tostring(raw.label or 'Radio Station'),
        icon   = tostring(raw.icon or 'fa-solid fa-tower-broadcast'),
    }
end

--- Copies and validates a station definition, dropping unknown fields.
---@param raw any
---@return Station|nil station, string|nil error
local function normalizeStation(raw)
    if type(raw) ~= 'table' then return nil, 'station must be a table' end

    local id = tostring(raw.id or ''):gsub('%s+', '')
    if id == '' then return nil, 'station id is required' end

    local label = tostring(raw.label or '')
    if label == '' then return nil, 'station label is required' end

    local frequency = tonumber(raw.frequency)
    if not frequency then return nil, 'station frequency must be a number' end

    local zones = {}
    for _, zone in ipairs(type(raw.zones) == 'table' and raw.zones or {}) do
        zones[#zones + 1] = normalizeZone(zone)
    end

    local targets = {}
    for _, target in ipairs(type(raw.targets) == 'table' and raw.targets or {}) do
        targets[#targets + 1] = normalizeTarget(target)
    end

    local hostJobs = {}
    for _, job in ipairs(type(raw.hostJobs) == 'table' and raw.hostJobs or {}) do
        local name = tostring(job):gsub('%s+', '')
        if name ~= '' then hostJobs[#hostJobs + 1] = name end
    end

    return {
        id          = id,
        label       = label,
        frequency   = math.floor(frequency),
        streamUrl   = tostring(raw.streamUrl or ''),
        icon        = tostring(raw.icon or 'radio'),
        description = tostring(raw.description or ''),
        hostJobs    = hostJobs,
        zones       = zones,
        targets     = targets,
    }
end

--- Server-side station store: normalisation, persistence, permissions and sync.
---@class StationStore : OxClass
---@field private stations Station[]
local StationStore = lib.class('StationStore')

--- Loads the persisted list (or config defaults) into memory.
function StationStore:constructor()
    self.stations = {}
    self:load()
end

--- Rebuilds the in-memory list from the server config defaults.
function StationStore:seedFromConfig()
    self.stations = {}
    for _, raw in ipairs(ServerConfig.stations) do
        local station, err = normalizeStation(raw)
        if station then
            self.stations[#self.stations + 1] = station
        else
            print(('[cad-radiostation] skipping invalid config station: %s'):format(err))
        end
    end
end

--- Writes the current list to the KVP store.
function StationStore:save()
    if not ServerConfig.persistStations then return end
    SetResourceKvp(KVP_KEY, json.encode(self.stations))
end

--- Restores the list from KVP, falling back to the config defaults.
function StationStore:load()
    if not ServerConfig.persistStations then
        self:seedFromConfig()
        return
    end

    local stored = GetResourceKvpString(KVP_KEY)
    local decoded = stored and json.decode(stored)

    if type(decoded) ~= 'table' or #decoded == 0 then
        self:seedFromConfig()
        self:save()
        return
    end

    self.stations = {}
    for _, raw in ipairs(decoded) do
        local station = normalizeStation(raw)
        if station then self.stations[#self.stations + 1] = station end
    end
end

--- Whether the player belongs to a group listed in the server config.
---@param source number
---@return boolean
local function isStaff(source)
    local player = GetPlayer(source)
    return player ~= nil and ServerConfig.adminGroups[player.group] == true
end

--- Returns the live station list, which should be treated as read-only.
---@return Station[]
function StationStore:getAll()
    return self.stations
end

--- Finds a station by id.
---@param stationId string
---@return Station|nil station, number|nil index
function StationStore:getById(stationId)
    for index, station in ipairs(self.stations) do
        if station.id == stationId then return station, index end
    end
    return nil, nil
end

--- Finds a station by frequency.
---@param frequency number
---@return Station|nil station, number|nil index
function StationStore:getByFrequency(frequency)
    for index, station in ipairs(self.stations) do
        if station.frequency == frequency then return station, index end
    end
    return nil, nil
end

--- Whether the player may broadcast on a frequency.
---@param source number
---@param frequency number
---@return boolean
function StationStore:canBroadcast(source, frequency)
    if IsPlayerAceAllowed(tostring(source), ServerConfig.hostAcePermission) then return true end

    local station = self:getByFrequency(frequency)
    if not station then return false end

    local player = GetPlayer(source)
    if not player then return false end
    if ServerConfig.adminGroups[player.group] then return true end

    for _, job in ipairs(station.hostJobs) do
        if player.job == job then return true end
    end
    return false
end

--- Whether the player may create, edit or delete stations.
---@param source number
---@return boolean
function StationStore:canEdit(source)
    return IsPlayerAceAllowed(tostring(source), ServerConfig.editorAcePermission) or isStaff(source)
end

--- Builds the station list a player is allowed to see, without URLs or host jobs.
---@param source number
---@return ClientStation[]
function StationStore:buildClientList(source)
    local list = {}
    for index, station in ipairs(self.stations) do
        list[index] = {
            id           = station.id,
            label        = station.label,
            frequency    = station.frequency,
            icon         = station.icon,
            description  = station.description,
            zones        = station.zones,
            targets      = station.targets,
            canBroadcast = self:canBroadcast(source, station.frequency),
        }
    end
    return list
end

--- Pushes the station list to one player, or to everyone when source is nil.
---@param source number|nil
function StationStore:sync(source)
    if source then
        TriggerClientEvent('cad-radiostation:stations', source, self:buildClientList(source))
        return
    end

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        TriggerClientEvent('cad-radiostation:stations', target, self:buildClientList(target))
    end
end

--- Creates or replaces a station after validating id and frequency uniqueness.
---@param source number
---@param payload table Raw station sent by the editor
---@param originalId string|nil Id being edited, nil when creating
---@return boolean ok, string|nil error
function StationStore:upsert(source, payload, originalId)
    local station, err = normalizeStation(payload)
    if not station then return false, err end

    for _, existing in ipairs(self.stations) do
        if existing.id ~= originalId then
            if existing.id == station.id then
                return false, ('station id "%s" is already in use'):format(station.id)
            end
            if existing.frequency == station.frequency then
                return false, ('frequency %d is already used by "%s"'):format(station.frequency, existing.label)
            end
        end
    end

    local _, index = self:getById(originalId or station.id)
    if index then
        self.stations[index] = station
    else
        self.stations[#self.stations + 1] = station
    end

    self:save()
    self:sync()
    Debug(('player %d saved station %s'):format(source, station.id))
    return true, nil
end

--- Deletes a station by id and notifies the broadcast layer.
---@param stationId string
---@return Station|nil removed
function StationStore:delete(stationId)
    local station, index = self:getById(stationId)
    if not station or not index then return nil end

    table.remove(self.stations, index)
    self:save()
    self:sync()
    TriggerEvent('cad-radiostation:internal:stationRemoved', station.frequency)
    return station
end

--- Discards in-game edits and restores the config defaults.
function StationStore:reset()
    self:seedFromConfig()
    self:save()
    self:sync()
end

--- Singleton store shared by the server modules.
Stations = StationStore:new()

RegisterNetEvent('cad-radiostation:editor:save', function(payload, originalId)
    local source = source
    if not Stations:canEdit(source) then
        Notify(source, 'You are not allowed to edit stations', 'error')
        return
    end

    local ok, err = Stations:upsert(source, payload, originalId)
    Notify(source, ok and 'Station saved' or ('Save failed: ' .. (err or 'unknown')), ok and 'success' or 'error')
end)

RegisterNetEvent('cad-radiostation:editor:delete', function(stationId)
    local source = source
    if not Stations:canEdit(source) then
        Notify(source, 'You are not allowed to edit stations', 'error')
        return
    end

    local station = Stations:delete(stationId)
    if not station then
        Notify(source, 'Station not found', 'error')
        return
    end

    Notify(source, ('Deleted "%s"'):format(station.label), 'success')
    Debug(('player %d deleted station %s'):format(source, stationId))
end)

RegisterNetEvent('cad-radiostation:editor:reset', function()
    local source = source
    if not Stations:canEdit(source) then
        Notify(source, 'You are not allowed to edit stations', 'error')
        return
    end

    Stations:reset()
    Notify(source, 'Stations reset to config defaults', 'success')
    Debug(('player %d reset stations to defaults'):format(source))
end)

RegisterNetEvent('cad-radiostation:requestStations', function()
    Stations:sync(source)
end)

lib.callback.register('cad-radiostation:getStations', function(source)
    return Stations:buildClientList(source)
end)

lib.callback.register('cad-radiostation:canEdit', function(source)
    return Stations:canEdit(source)
end)

--- Full record for the editor, including fields hidden from the normal list.
lib.callback.register('cad-radiostation:getStationForEdit', function(source, stationId)
    if not Stations:canEdit(source) then return nil end
    return (Stations:getById(stationId))
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Stations:sync()
    Debug(('loaded %d stations'):format(#Stations:getAll()))
end)

exports('GetStations', function()
    return Stations:getAll()
end)

exports('GetStationById', function(stationId)
    return (Stations:getById(stationId))
end)

exports('GetStationByFrequency', function(frequency)
    return (Stations:getByFrequency(frequency))
end)
