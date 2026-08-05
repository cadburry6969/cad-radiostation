---@type table<number, { stationId: string, frequency: number, volume: number }>
local listeners = {}

---@type table<number, { source: number, mode: BroadcastMode, broadcastUrl: string|nil }>
local broadcasters = {}

--- Collects the sources of every listener tuned to a frequency.
---@param frequency number
---@return number[]
local function getListenersOnFrequency(frequency)
    local result = {}
    for src, data in pairs(listeners) do
        if data.frequency == frequency then
            result[#result + 1] = src
        end
    end
    return result
end

--- Ends the broadcast on a frequency and returns every listener to the default stream.
---@param frequency number
local function clearBroadcast(frequency)
    local broadcast = broadcasters[frequency]
    if not broadcast then return end

    local mode = broadcast.mode
    broadcasters[frequency] = nil

    local station = Stations.GetByFrequency(frequency)
    local defaultUrl = station and station.streamUrl or ''

    for _, listenerSrc in ipairs(getListenersOnFrequency(frequency)) do
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
local function validateBroadcastRequest(source, frequency)
    if not Stations.CanBroadcast(source, frequency) then
        Notify(source, 'You do not have permission to broadcast', 'error')
        return nil
    end

    local station = Stations.GetByFrequency(frequency)
    if not station then
        Notify(source, 'Invalid frequency', 'error')
        return nil
    end

    if broadcasters[frequency] and broadcasters[frequency].source ~= source then
        Notify(source, 'Someone is already broadcasting on this frequency', 'error')
        return nil
    end

    return station
end

RegisterNetEvent('cad-radiostation:tuneStation', function(stationId)
    local source = source
    local station = Stations.GetById(stationId)
    if not station then
        Notify(source, 'Station not found', 'error')
        return
    end

    -- Detach from the previous frequency before joining the new one.
    local previous = listeners[source]
    if previous then
        local oldBroadcast = broadcasters[previous.frequency]
        if oldBroadcast and oldBroadcast.mode == 'voice' then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', oldBroadcast.source, source)
        end
    end

    local volume = previous and previous.volume or Config.defaultVolume
    listeners[source] = {
        stationId = station.id,
        frequency = station.frequency,
        volume    = volume,
    }

    local broadcast = broadcasters[station.frequency]
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
end)

RegisterNetEvent('cad-radiostation:leaveStation', function()
    local source = source
    local data = listeners[source]
    if not data then return end

    listeners[source] = nil

    local broadcast = broadcasters[data.frequency]
    if broadcast and broadcast.mode == 'voice' then
        TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcast.source, source)
    end

    TriggerClientEvent('cad-radiostation:stationLeft', source)
    Debug(('player %d left station %s'):format(source, data.stationId))
end)

RegisterNetEvent('cad-radiostation:updateVolume', function(volume)
    local source = source
    volume = tonumber(volume)
    if not volume or not listeners[source] then return end
    listeners[source].volume = math.max(0, math.min(100, math.floor(volume)))
end)

RegisterNetEvent('cad-radiostation:startVoiceBroadcast', function(frequency)
    local source = source
    local station = validateBroadcastRequest(source, frequency)
    if not station then return end

    broadcasters[frequency] = { source = source, mode = 'voice' }

    local listenerList = {}
    for _, listenerSrc in ipairs(getListenersOnFrequency(frequency)) do
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
end)

RegisterNetEvent('cad-radiostation:startUrlBroadcast', function(frequency, broadcastUrl)
    local source = source

    if type(broadcastUrl) ~= 'string' or broadcastUrl == '' then
        Notify(source, 'No broadcast URL provided', 'error')
        return
    end

    local station = validateBroadcastRequest(source, frequency)
    if not station then return end

    broadcasters[frequency] = { source = source, mode = 'url', broadcastUrl = broadcastUrl }

    for _, listenerSrc in ipairs(getListenersOnFrequency(frequency)) do
        TriggerClientEvent('cad-radiostation:switchStream', listenerSrc, {
            frequency   = frequency,
            streamUrl   = broadcastUrl,
            isBroadcast = true,
        })
    end

    Notify(source, ('URL broadcasting on %s (%d)'):format(station.label, frequency), 'success')
    Debug(('player %d URL broadcasting on freq %d'):format(source, frequency))
end)

RegisterNetEvent('cad-radiostation:stopBroadcast', function(frequency)
    local source = source
    if not broadcasters[frequency] or broadcasters[frequency].source ~= source then return end
    clearBroadcast(frequency)
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(targetPeerId, signalData)
    local source = source
    TriggerClientEvent('cad-radiostation:webrtc:signal', targetPeerId, source, signalData)
end)

lib.callback.register('cad-radiostation:canBroadcast', function(source, frequency)
    return Stations.CanBroadcast(source, frequency)
end)

lib.callback.register('cad-radiostation:getBroadcastState', function(source, frequency)
    local broadcast = broadcasters[frequency]
    if not broadcast then return { active = false } end
    return {
        active            = true,
        mode              = broadcast.mode,
        broadcasterSource = broadcast.source,
    }
end)

-- A deleted station must not leave listeners stuck on a dead frequency.
AddEventHandler('cad-radiostation:internal:stationRemoved', function(frequency)
    clearBroadcast(frequency)
    for src, data in pairs(listeners) do
        if data.frequency == frequency then
            listeners[src] = nil
            TriggerClientEvent('cad-radiostation:stationLeft', src)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local source = source

    local data = listeners[source]
    if data then
        local broadcast = broadcasters[data.frequency]
        if broadcast and broadcast.mode == 'voice' and broadcast.source ~= source then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcast.source, source)
        end
        listeners[source] = nil
    end

    for frequency, broadcast in pairs(broadcasters) do
        if broadcast.source == source then
            clearBroadcast(frequency)
        end
    end
end)
