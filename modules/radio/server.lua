--- Server broadcast manager: listener routing and voice/URL broadcast state.
---@class BroadcastManager : OxClass
---@field private listeners table<number, { stationId: string, frequency: number, volume: number }>
---@field private broadcasters table<number, { source: number, mode: BroadcastMode, broadcastUrl: string|nil }>
local BroadcastManager = lib.class('BroadcastManager')

--- Initialises empty listener and broadcaster tables.
function BroadcastManager:constructor()
    self.listeners = {}
    self.broadcasters = {}
end

--- Collects the sources of every listener tuned to a frequency.
---@param frequency number
---@return number[]
function BroadcastManager:getListenersOnFrequency(frequency)
    local result = {}
    for src, data in pairs(self.listeners) do
        if data.frequency == frequency then
            result[#result + 1] = src
        end
    end
    return result
end

--- Ends the broadcast on a frequency and returns every listener to the default stream.
---@param frequency number
function BroadcastManager:clearBroadcast(frequency)
    local broadcast = self.broadcasters[frequency]
    if not broadcast then return end

    local mode = broadcast.mode
    self.broadcasters[frequency] = nil

    local station = Stations:getByFrequency(frequency)
    local defaultUrl = station and station.streamUrl or ''

    for _, listenerSrc in ipairs(self:getListenersOnFrequency(frequency)) do
        if mode == 'voice' then
            TriggerClientEvent('cad-radiostation:broadcastStopped', listenerSrc, {
                frequency = frequency,
                streamUrl = defaultUrl,
            })
        else
            TriggerClientEvent('cad-radiostation:switchStream', listenerSrc, {
                frequency   = frequency,
                streamUrl   = defaultUrl,
                isBroadcast = false,
            })
        end
    end

    Debug(('cleared %s broadcast on freq %d'):format(mode, frequency))
end

--- Shared guard for both broadcast modes.
---@param source number
---@param frequency number
---@return Station|nil station Nil when the request must be rejected
function BroadcastManager:validateRequest(source, frequency)
    if not Stations:canBroadcast(source, frequency) then
        Notify(source, 'You do not have permission to broadcast', 'error')
        return nil
    end

    local station = Stations:getByFrequency(frequency)
    if not station then
        Notify(source, 'Invalid frequency', 'error')
        return nil
    end

    local broadcast = self.broadcasters[frequency]
    if broadcast and broadcast.source ~= source then
        Notify(source, 'Someone is already broadcasting on this frequency', 'error')
        return nil
    end

    return station
end

--- Tunes a player to a station, detaching from any previous frequency first.
---@param source number
---@param stationId string
function BroadcastManager:tune(source, stationId)
    local station = Stations:getById(stationId)
    if not station then
        Notify(source, 'Station not found', 'error')
        return
    end

    -- Detach from the previous frequency before joining the new one.
    local previous = self.listeners[source]
    if previous then
        local oldBroadcast = self.broadcasters[previous.frequency]
        if oldBroadcast and oldBroadcast.mode == 'voice' then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', oldBroadcast.source, source)
        end
    end

    local volume = previous and previous.volume or Config.defaultVolume
    self.listeners[source] = {
        stationId = station.id,
        frequency = station.frequency,
        volume    = volume,
    }

    local broadcast = self.broadcasters[station.frequency]
    local activeUrl = station.streamUrl

    if broadcast and broadcast.mode == 'url' and broadcast.broadcastUrl then
        activeUrl = broadcast.broadcastUrl
    end

    TriggerClientEvent('cad-radiostation:stationTuned', source, {
        stationId      = station.id,
        label          = station.label,
        frequency      = station.frequency,
        streamUrl      = activeUrl,
        volume         = volume,
        isBroadcasting = broadcast ~= nil,
        broadcastMode  = broadcast and broadcast.mode or nil,
    })

    if broadcast and broadcast.mode == 'voice' then
        TriggerClientEvent('cad-radiostation:webrtc:createOffer', broadcast.source, source)
    end

    Debug(('player %d tuned to %s (freq %d)'):format(source, station.label, station.frequency))
end

--- Removes a player as a listener and closes any voice peer.
---@param source number
function BroadcastManager:leave(source)
    local data = self.listeners[source]
    if not data then return end

    self.listeners[source] = nil

    local broadcast = self.broadcasters[data.frequency]
    if broadcast and broadcast.mode == 'voice' then
        TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcast.source, source)
    end

    TriggerClientEvent('cad-radiostation:stationLeft', source)
    Debug(('player %d left station %s'):format(source, data.stationId))
end

--- Persists a listener's chosen volume (0-100).
---@param source number
---@param volume number
function BroadcastManager:setVolume(source, volume)
    volume = tonumber(volume)
    if not volume or not self.listeners[source] then return end
    self.listeners[source].volume = math.max(0, math.min(100, math.floor(volume)))
end

--- Starts a voice broadcast and arms every current listener.
---@param source number
---@param frequency number
function BroadcastManager:startVoice(source, frequency)
    local station = self:validateRequest(source, frequency)
    if not station then return end

    self.broadcasters[frequency] = { source = source, mode = 'voice' }

    local listenerList = {}
    for _, listenerSrc in ipairs(self:getListenersOnFrequency(frequency)) do
        if listenerSrc ~= source then
            listenerList[#listenerList + 1] = listenerSrc
            TriggerClientEvent('cad-radiostation:broadcastStarted', listenerSrc, {
                frequency = frequency,
                mode      = 'voice',
            })
        end
    end

    TriggerClientEvent('cad-radiostation:voiceBroadcastApproved', source, {
        frequency = frequency,
        listeners = listenerList,
    })

    Notify(source, ('Voice broadcasting on %s (%d)'):format(station.label, frequency), 'success')
    Debug(('player %d voice broadcasting on freq %d to %d listeners'):format(source, frequency, #listenerList))
end

--- Starts a URL broadcast and switches every listener to the given stream.
---@param source number
---@param frequency number
---@param broadcastUrl string
function BroadcastManager:startUrl(source, frequency, broadcastUrl)
    if type(broadcastUrl) ~= 'string' or broadcastUrl == '' then
        Notify(source, 'No broadcast URL provided', 'error')
        return
    end

    local station = self:validateRequest(source, frequency)
    if not station then return end

    self.broadcasters[frequency] = { source = source, mode = 'url', broadcastUrl = broadcastUrl }

    for _, listenerSrc in ipairs(self:getListenersOnFrequency(frequency)) do
        TriggerClientEvent('cad-radiostation:switchStream', listenerSrc, {
            frequency   = frequency,
            streamUrl   = broadcastUrl,
            isBroadcast = true,
        })
    end

    Notify(source, ('URL broadcasting on %s (%d)'):format(station.label, frequency), 'success')
    Debug(('player %d URL broadcasting on freq %d'):format(source, frequency))
end

--- Stops a broadcast owned by the given source.
---@param source number
---@param frequency number
function BroadcastManager:stop(source, frequency)
    local broadcast = self.broadcasters[frequency]
    if not broadcast or broadcast.source ~= source then return end
    self:clearBroadcast(frequency)
end

--- Reports whether a frequency is being broadcast on and by whom.
---@param frequency number
---@return BroadcastState
function BroadcastManager:getState(frequency)
    local broadcast = self.broadcasters[frequency]
    if not broadcast then return { active = false } end
    return {
        active            = true,
        mode              = broadcast.mode,
        broadcasterSource = broadcast.source,
    }
end

--- Drops every listener from a removed frequency and clears its broadcast.
---@param frequency number
function BroadcastManager:removeFrequency(frequency)
    self:clearBroadcast(frequency)
    for src, data in pairs(self.listeners) do
        if data.frequency == frequency then
            self.listeners[src] = nil
            TriggerClientEvent('cad-radiostation:stationLeft', src)
        end
    end
end

--- Cleans up a disconnected player's listener and broadcaster state.
---@param source number
function BroadcastManager:handleDrop(source)
    local data = self.listeners[source]
    if data then
        local broadcast = self.broadcasters[data.frequency]
        if broadcast and broadcast.mode == 'voice' and broadcast.source ~= source then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcast.source, source)
        end
        self.listeners[source] = nil
    end

    for frequency, broadcast in pairs(self.broadcasters) do
        if broadcast.source == source then
            self:clearBroadcast(frequency)
        end
    end
end

local manager = BroadcastManager:new()

RegisterNetEvent('cad-radiostation:tuneStation', function(stationId)
    manager:tune(source, stationId)
end)

RegisterNetEvent('cad-radiostation:leaveStation', function()
    manager:leave(source)
end)

RegisterNetEvent('cad-radiostation:updateVolume', function(volume)
    manager:setVolume(source, volume)
end)

RegisterNetEvent('cad-radiostation:startVoiceBroadcast', function(frequency)
    manager:startVoice(source, frequency)
end)

RegisterNetEvent('cad-radiostation:startUrlBroadcast', function(frequency, broadcastUrl)
    manager:startUrl(source, frequency, broadcastUrl)
end)

RegisterNetEvent('cad-radiostation:stopBroadcast', function(frequency)
    manager:stop(source, frequency)
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(targetPeerId, signalData)
    TriggerClientEvent('cad-radiostation:webrtc:signal', targetPeerId, source, signalData)
end)

lib.callback.register('cad-radiostation:canBroadcast', function(source, frequency)
    return Stations:canBroadcast(source, frequency)
end)

lib.callback.register('cad-radiostation:getBroadcastState', function(_, frequency)
    return manager:getState(frequency)
end)

-- A deleted station must not leave listeners stuck on a dead frequency.
AddEventHandler('cad-radiostation:internal:stationRemoved', function(frequency)
    manager:removeFrequency(frequency)
end)

AddEventHandler('playerDropped', function()
    manager:handleDrop(source)
end)
