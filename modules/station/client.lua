--- Client-side station cache plus the world zones and target points built from it.
---@class StationCache : OxClass
---@field private cache ClientStation[]
---@field private byId table<string, ClientStation>
---@field private occupiedZones table<string, true> Ids of zones the player is inside
---@field private zoneHandles table[] Handles returned by lib.zones.box
---@field private targetHandles { resource: string, handle: any }[]
local StationCache = lib.class('StationCache')

--- Initialises empty caches and handle lists.
function StationCache:constructor()
    self.cache = {}
    self.byId = {}
    self.occupiedZones = {}
    self.zoneHandles = {}
    self.targetHandles = {}
end

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
function StationCache:getAll()
    return self.cache
end

--- Finds a station by id.
---@param stationId string
---@return ClientStation|nil
function StationCache:getById(stationId)
    return self.byId[stationId]
end

--- Whether the player is standing in any station's broadcast zone.
---@return boolean
function StationCache:isInAnyZone()
    return next(self.occupiedZones) ~= nil
end

--- The station whose zone the player occupies and may operate, if any.
---@return ClientStation|nil
function StationCache:getCurrentZoneStation()
    for stationId in pairs(self.occupiedZones) do
        local station = self.byId[stationId]
        if station and station.canBroadcast then return station end
    end
    return nil
end

--- Removes every zone and target created from the previous station list.
function StationCache:destroyWorldGeometry()
    for _, zone in ipairs(self.zoneHandles) do
        zone:remove()
    end
    self.zoneHandles = {}

    for _, entry in ipairs(self.targetHandles) do
        if entry.resource == 'ox_target' then
            exports.ox_target:removeZone(entry.handle)
        else
            exports['qb-target']:RemoveZone(entry.handle)
        end
    end
    self.targetHandles = {}

    self.occupiedZones = {}
end

--- Creates the broadcast zones for one station.
---@param station ClientStation
function StationCache:createZones(station)
    for _, zone in ipairs(station.zones) do
        self.zoneHandles[#self.zoneHandles + 1] = lib.zones.box({
            coords   = toVec3(zone.coords),
            size     = toVec3(zone.size),
            rotation = zone.heading or 0.0,
            debug    = ClientConfig.zoneDebug,

            onEnter = function()
                self.occupiedZones[station.id] = true
                Debug('entered broadcast zone for', station.label)
            end,

            onExit = function()
                self.occupiedZones[station.id] = nil
                Debug('left broadcast zone for', station.label)

                -- A host may not keep transmitting after walking out of the studio
                if Radio:getBroadcastFrequency() == station.frequency then
                    Radio:stopBroadcast('Broadcast stopped: you left the studio')
                end
            end,
        })
    end
end

--- Creates the interaction points for one station.
---@param station ClientStation
---@param targetResource 'ox_target'|'qb-target'
function StationCache:createTargets(station, targetResource)
    for index, target in ipairs(station.targets) do
        local coords = toVec3(target.coords)

        -- Read from the cache so the check follows live permission updates
        local function canInteract()
            local current = self.byId[station.id]
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
                        onSelect    = function() Radio:openStationPanel(station.id) end,
                        canInteract = canInteract,
                    },
                },
            })
            self.targetHandles[#self.targetHandles + 1] = { resource = 'ox_target', handle = handle }
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
                        action      = function() Radio:openStationPanel(station.id) end,
                        canInteract = canInteract,
                    },
                },
                distance = math.max(2.0, target.radius + 1.0),
            })
            self.targetHandles[#self.targetHandles + 1] = { resource = 'qb-target', handle = name }
        end
    end
end

--- Replaces the cache and rebuilds all zones and targets from it.
---@param stations ClientStation[]
function StationCache:apply(stations)
    self:destroyWorldGeometry()

    self.cache = stations or {}
    self.byId = {}

    local targetResource = getTargetResource()

    for _, station in ipairs(self.cache) do
        self.byId[station.id] = station
        self:createZones(station)
        if targetResource then
            self:createTargets(station, targetResource)
        end
    end

    Debug(('applied %d stations'):format(#self.cache))
end

--- Singleton cache shared by the client modules.
Stations = StationCache:new()

RegisterNetEvent('cad-radiostation:stations', function(stations)
    Stations:apply(stations)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Stations:destroyWorldGeometry()
end)

exports('GetCurrentStation', function()
    return Radio:getCurrentStation()
end)

exports('IsListening', function()
    return Radio:getCurrentStation() ~= nil
end)

exports('GetVolume', function()
    return Radio:getVolume()
end)

exports('GetStations', function()
    return Stations:getAll()
end)

exports('TuneToStation', function(stationId)
    Radio:tuneToStation(stationId)
end)

exports('LeaveStation', function()
    Radio:leaveStation()
end)

exports('OpenRadioMenu', function()
    Radio:openVehicleRadio()
end)

exports('OpenStationPanel', function(stationId)
    Radio:openStationPanel(stationId)
end)
