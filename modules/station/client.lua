---@class StationCache
Stations = {}

---@type ClientStation[]
local cache = {}

---@type table<string, ClientStation> Indexed by station id for O(1) lookups
local byId = {}

---@type table<string, true> Ids of the stations whose zone the player is inside
local occupiedZones = {}

---@type table[] Handles returned by lib.zones.box
local zoneHandles = {}

---@type { resource: string, handle: any }[] Handles returned by the target resource
local targetHandles = {}

--- Converts a stored {x,y,z} table into a vector3.
---@param coords { x: number, y: number, z: number }
---@return vector3
local function toVec3(coords)
    return vec3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

--- Name of the target resource in use, or nil when none is running.
---@return 'ox_target'|'qb-target'|nil
local function getTargetResource()
    if GetResourceState('ox_target') == 'started' then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' then return 'qb-target' end
    return nil
end

--- The station list this player is allowed to see.
---@return ClientStation[]
function Stations.GetAll()
    return cache
end

--- Finds a station by id.
---@param stationId string
---@return ClientStation|nil
function Stations.GetById(stationId)
    return byId[stationId]
end

--- Whether the player is standing in any station's broadcast zone.
---@return boolean
function Stations.IsInAnyZone()
    return next(occupiedZones) ~= nil
end

--- The station whose zone the player occupies and may operate, if any.
---@return ClientStation|nil
function Stations.GetCurrentZoneStation()
    for stationId in pairs(occupiedZones) do
        local station = byId[stationId]
        if station and station.canBroadcast then return station end
    end
    return nil
end

--- Removes every zone and target created from the previous station list.
local function destroyWorldGeometry()
    for _, zone in ipairs(zoneHandles) do
        zone:remove()
    end
    zoneHandles = {}

    for _, entry in ipairs(targetHandles) do
        if entry.resource == 'ox_target' then
            exports.ox_target:removeZone(entry.handle)
        else
            exports['qb-target']:RemoveZone(entry.handle)
        end
    end
    targetHandles = {}

    occupiedZones = {}
end

--- Creates the broadcast zones for one station.
---@param station ClientStation
local function createZones(station)
    for _, zone in ipairs(station.zones) do
        zoneHandles[#zoneHandles + 1] = lib.zones.box({
            coords   = toVec3(zone.coords),
            size     = toVec3(zone.size),
            rotation = zone.heading or 0.0,
            debug    = ClientConfig.zoneDebug,

            onEnter = function()
                occupiedZones[station.id] = true
                Debug('entered broadcast zone for', station.label)
            end,

            onExit = function()
                occupiedZones[station.id] = nil
                Debug('left broadcast zone for', station.label)

                -- A host may not keep transmitting after walking out of the studio
                if Radio.GetBroadcastFrequency() == station.frequency then
                    Radio.StopBroadcast('Broadcast stopped: you left the studio')
                end
            end,
        })
    end
end

--- Creates the interaction points for one station.
---@param station ClientStation
---@param targetResource 'ox_target'|'qb-target'
local function createTargets(station, targetResource)
    for index, target in ipairs(station.targets) do
        local coords = toVec3(target.coords)

        -- Read from the cache so the check follows live permission updates
        local function canInteract()
            local current = byId[station.id]
            return current ~= nil and current.canBroadcast
        end

        if targetResource == 'ox_target' then
            local handle = exports.ox_target:addSphereZone({
                coords  = coords,
                radius  = target.radius,
                options = {
                    {
                        label       = target.label,
                        icon        = target.icon,
                        onSelect    = function() Radio.OpenStationPanel(station.id) end,
                        canInteract = canInteract,
                    },
                },
            })
            targetHandles[#targetHandles + 1] = { resource = 'ox_target', handle = handle }
        else
            local name = ('cad-radiostation:%s:%d'):format(station.id, index)
            exports['qb-target']:AddCircleZone(name, coords, target.radius, {
                name = name,
                useZ = true,
            }, {
                options = {
                    {
                        label       = target.label,
                        icon        = target.icon,
                        action      = function() Radio.OpenStationPanel(station.id) end,
                        canInteract = canInteract,
                    },
                },
                distance = math.max(2.0, target.radius + 1.0),
            })
            targetHandles[#targetHandles + 1] = { resource = 'qb-target', handle = name }
        end
    end
end

--- Replaces the cache and rebuilds all zones and targets from it.
---@param stations ClientStation[]
local function applyStations(stations)
    destroyWorldGeometry()

    cache = stations or {}
    byId = {}

    local targetResource = getTargetResource()

    for _, station in ipairs(cache) do
        byId[station.id] = station
        createZones(station)
        if targetResource then
            createTargets(station, targetResource)
        end
    end

    Debug(('applied %d stations'):format(#cache))
end

RegisterNetEvent('cad-radiostation:stations', function(stations)
    applyStations(stations)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    destroyWorldGeometry()
end)

exports('GetCurrentStation', function()
    return Radio.GetCurrentStation()
end)

exports('IsListening', function()
    return Radio.GetCurrentStation() ~= nil
end)

exports('GetVolume', function()
    return Radio.GetVolume()
end)

exports('GetStations', function()
    return cache
end)

exports('TuneToStation', function(stationId)
    Radio.TuneToStation(stationId)
end)

exports('LeaveStation', function()
    Radio.LeaveStation()
end)

exports('OpenRadioMenu', function()
    Radio.OpenVehicleRadio()
end)

exports('OpenStationPanel', function(stationId)
    Radio.OpenStationPanel(stationId)
end)
