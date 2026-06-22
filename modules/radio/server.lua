local listeners = {}
local broadcasters = {}

--- Returns the station config matching the given ID.
---@param stationId string
---@return table|nil
local function GetStationById(stationId)
    for _, station in ipairs(Config.Stations) do
        if station.id == stationId then return station end
    end
    return nil
end

--- Returns the station config matching the given frequency.
---@param frequency number
---@return table|nil
local function GetStationByFrequency(frequency)
    for _, station in ipairs(Config.Stations) do
        if station.frequency == frequency then return station end
    end
    return nil
end

--- Returns a table of all listener sources tuned to the given frequency.
---@param frequency number
---@return table<number, boolean>
local function GetListenersOnFrequency(frequency)
    local result = {}
    for src, data in pairs(listeners) do
        if data.frequency == frequency then
            result[src] = true
        end
    end
    return result
end

--- Checks if the given source has broadcast permission for a specific frequency.
---@param source number
---@param frequency number
---@return boolean
local function CanBroadcast(source, frequency)
    if IsPlayerAceAllowed(tostring(source), Config.HostAcePermission) then
        return true
    end

    local station = GetStationByFrequency(frequency)
    if not station or not station.hostJobs then return false end

    local player = GetPlayer(source)
    if player then
        for _, job in ipairs(station.hostJobs) do
            if player.job == job then return true end
        end
        if player.group == 'admin' or player.group == 'superadmin' or player.group == 'god' then
            return true
        end
    end
    return false
end

RegisterNetEvent('cad-radiostation:tuneStation', function(stationId)
    local source = source
    local station = GetStationById(stationId)
    if not station then
        Notify(source, 'Station not found', 'error')
        return
    end

    if listeners[source] then
        local oldFreq = listeners[source].frequency
        if broadcasters[oldFreq] and broadcasters[oldFreq].mode == 'voice' then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcasters[oldFreq].source, source)
        end
        listeners[source] = nil
    end

    listeners[source] = {
        stationId = station.id,
        frequency = station.frequency,
        volume    = Config.DefaultVolume,
    }

    local activeUrl = station.streamUrl
    local isBroadcasting = false
    local broadcastMode = nil
    local broadcasterSrc = nil

    if broadcasters[station.frequency] then
        isBroadcasting = true
        broadcastMode = broadcasters[station.frequency].mode
        broadcasterSrc = broadcasters[station.frequency].source

        if broadcastMode == 'url' and broadcasters[station.frequency].broadcastUrl then
            activeUrl = broadcasters[station.frequency].broadcastUrl
        end
    end

    TriggerClientEvent('cad-radiostation:stationTuned', source, {
        stationId      = station.id,
        label          = station.label,
        frequency      = station.frequency,
        streamUrl      = activeUrl,
        volume         = Config.DefaultVolume,
        isBroadcasting = isBroadcasting,
        broadcastMode  = broadcastMode,
    })

    if isBroadcasting and broadcastMode == 'voice' and broadcasterSrc then
        TriggerClientEvent('cad-radiostation:webrtc:createOffer', broadcasterSrc, source)
    end

    if Config.Debug then
        print(('[cad-radiostation] Player %d tuned to %s (freq %d)'):format(source, station.label, station.frequency))
    end
end)

RegisterNetEvent('cad-radiostation:leaveStation', function()
    local source = source
    if not listeners[source] then return end

    local data = listeners[source]
    listeners[source] = nil

    if broadcasters[data.frequency] and broadcasters[data.frequency].mode == 'voice' then
        TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcasters[data.frequency].source, source)
    end

    TriggerClientEvent('cad-radiostation:stationLeft', source)

    if Config.Debug then
        print(('[cad-radiostation] Player %d left station %s'):format(source, data.stationId))
    end
end)

RegisterNetEvent('cad-radiostation:updateVolume', function(volume)
    local source = source
    if listeners[source] then listeners[source].volume = volume end
end)

RegisterNetEvent('cad-radiostation:startVoiceBroadcast', function(frequency)
    local source = source

    if not CanBroadcast(source, frequency) then
        Notify(source, 'You do not have permission to broadcast', 'error')
        return
    end

    local station = GetStationByFrequency(frequency)
    if not station then
        Notify(source, 'Invalid frequency', 'error')
        return
    end

    if broadcasters[frequency] and broadcasters[frequency].source ~= source then
        Notify(source, 'Someone is already broadcasting on this frequency', 'error')
        return
    end

    broadcasters[frequency] = {
        source = source,
        mode   = 'voice',
    }

    local listenerList = {}
    local listenersOnFreq = GetListenersOnFrequency(frequency)
    for listenerSrc, _ in pairs(listenersOnFreq) do
        if listenerSrc ~= source then
            listenerList[#listenerList + 1] = listenerSrc
            TriggerClientEvent('cad-radiostation:broadcastStarted', listenerSrc, {
                frequency = frequency,
                mode = 'voice',
            })
        end
    end

    TriggerClientEvent('cad-radiostation:voiceBroadcastApproved', source, {
        frequency = frequency,
        listeners = listenerList,
    })

    Notify(source, ('Voice broadcasting on %s (%d)'):format(station.label, frequency), 'success')

    if Config.Debug then
        print(('[cad-radiostation] Player %d voice broadcasting on freq %d, %d listeners'):format(
            source, frequency, #listenerList))
    end
end)

RegisterNetEvent('cad-radiostation:startUrlBroadcast', function(frequency, broadcastUrl)
    local source = source

    if not CanBroadcast(source, frequency) then
        Notify(source, 'You do not have permission to broadcast', 'error')
        return
    end

    local station = GetStationByFrequency(frequency)
    if not station then
        Notify(source, 'Invalid frequency', 'error')
        return
    end

    if broadcasters[frequency] and broadcasters[frequency].source ~= source then
        Notify(source, 'Someone is already broadcasting on this frequency', 'error')
        return
    end

    if not broadcastUrl or broadcastUrl == '' then
        Notify(source, 'No broadcast URL provided', 'error')
        return
    end

    broadcasters[frequency] = {
        source       = source,
        mode         = 'url',
        broadcastUrl = broadcastUrl,
    }

    local listenersOnFreq = GetListenersOnFrequency(frequency)
    for listenerSrc, _ in pairs(listenersOnFreq) do
        TriggerClientEvent('cad-radiostation:switchStream', listenerSrc, {
            frequency   = frequency,
            streamUrl   = broadcastUrl,
            isBroadcast = true,
        })
    end

    Notify(source, ('URL broadcasting on %s (%d)'):format(station.label, frequency), 'success')

    if Config.Debug then
        print(('[cad-radiostation] Player %d URL broadcasting on freq %d'):format(source, frequency))
    end
end)

RegisterNetEvent('cad-radiostation:stopBroadcast', function(frequency)
    local source = source

    if not broadcasters[frequency] or broadcasters[frequency].source ~= source then
        return
    end

    local mode = broadcasters[frequency].mode
    broadcasters[frequency] = nil
    local station = GetStationByFrequency(frequency)
    local defaultUrl = station and station.streamUrl or ''

    local listenersOnFreq = GetListenersOnFrequency(frequency)
    for listenerSrc, _ in pairs(listenersOnFreq) do
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

    if Config.Debug then
        print(('[cad-radiostation] Player %d stopped %s broadcast on freq %d'):format(source, mode, frequency))
    end
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(targetPeerId, signalData)
    local source = source
    TriggerClientEvent('cad-radiostation:webrtc:signal', targetPeerId, source, signalData)

    if Config.Debug then
        print(('[cad-radiostation] WebRTC signal %d → %d (%s)'):format(source, targetPeerId, signalData.type or '?'))
    end
end)

lib.callback.register('cad-radiostation:canBroadcast', function(source, frequency)
    return CanBroadcast(source, frequency)
end)

lib.callback.register('cad-radiostation:getBroadcastState', function(source, frequency)
    if broadcasters[frequency] then
        return {
            active = true,
            mode = broadcasters[frequency].mode,
            broadcasterSource = broadcasters[frequency].source,
        }
    end
    return { active = false }
end)

AddEventHandler('playerDropped', function()
    local source = source

    if listeners[source] then
        local freq = listeners[source].frequency
        if broadcasters[freq] and broadcasters[freq].mode == 'voice' then
            TriggerClientEvent('cad-radiostation:webrtc:closePeer', broadcasters[freq].source, source)
        end
        listeners[source] = nil
    end

    for freq, data in pairs(broadcasters) do
        if data.source == source then
            local mode = data.mode
            broadcasters[freq] = nil
            local station = GetStationByFrequency(freq)
            local defaultUrl = station and station.streamUrl or ''
            local listenersOnFreq = GetListenersOnFrequency(freq)

            for listenerSrc, _ in pairs(listenersOnFreq) do
                if mode == 'voice' then
                    TriggerClientEvent('cad-radiostation:broadcastStopped', listenerSrc, {
                        frequency = freq,
                        streamUrl = defaultUrl,
                    })
                else
                    TriggerClientEvent('cad-radiostation:switchStream', listenerSrc, {
                        frequency   = freq,
                        streamUrl   = defaultUrl,
                        isBroadcast = false,
                    })
                end
            end

            if Config.Debug then
                print(('[cad-radiostation] Broadcaster %d dropped, clearing freq %d'):format(source, freq))
            end
        end
    end
end)
