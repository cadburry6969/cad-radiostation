local currentStation = nil
local currentVolume = Config.DefaultVolume
local activeBroadcastZones = {} -- [frequency] = true
local isBroadcasting = false
local broadcastMode = nil
local broadcastFrequency = nil
local canPlayerBroadcast = false
local micReady = false
local inBroadcastingZone = false

local function IsInVehicle()
    return IsPedInAnyVehicle(PlayerPedId(), false)
end

local function DebugPrint(...)
    if Config.Debug then
        print('[cad-radiostation:client]', ...)
    end
end

--- Sends a play stream command to the NUI audio engine.
---@param url string The stream URL to play
---@param volume number|nil Volume level (0-100), defaults to currentVolume
local function PlayStream(url, volume)
    if not url or url == '' then return end
    SendNUIMessage({
        action = 'playStream',
        url    = url,
        volume = (volume or currentVolume) / 100,
    })
    DebugPrint('Playing stream:', url)
end

--- Stops the currently playing audio stream.
local function StopStream()
    SendNUIMessage({ action = 'stopStream' })
end

--- Sets the volume of the currently playing stream.
---@param volume number Volume level (0-100)
local function SetStreamVolume(volume)
    SendNUIMessage({ action = 'setVolume', volume = volume / 100 })
end

--- Requests the NUI to start microphone capture for voice broadcasting.
local function NUI_StartMic()
    SendNUIMessage({ action = 'startMic' })
end

--- Requests the NUI to stop microphone capture.
local function NUI_StopMic()
    SendNUIMessage({ action = 'stopMic' })
end

--- Sends a WebRTC offer creation request to the NUI for a specific listener.
---@param listenerId number The server ID of the listener
local function NUI_CreateOffer(listenerId)
    SendNUIMessage({ action = 'createOffer', listenerId = listenerId })
end

--- Closes the WebRTC peer connection for a specific peer.
---@param peerId number The server ID of the peer
local function NUI_ClosePeer(peerId)
    SendNUIMessage({ action = 'closePeer', peerId = peerId })
end

--- Closes all WebRTC peer connections.
local function NUI_CloseAll()
    SendNUIMessage({ action = 'closeAll' })
end

--- Forwards a WebRTC signaling message to the NUI layer.
---@param fromPeerId number The server ID of the signaling peer
---@param signalData table Signal data containing type, sdp, and/or candidate
local function NUI_ForwardSignal(fromPeerId, signalData)
    SendNUIMessage({
        action     = 'signal',
        fromPeerId = fromPeerId,
        signalType = signalData.type,
        sdp        = signalData.sdp,
        candidate  = signalData.candidate,
    })
end

RegisterNUICallback('micCaptured', function(data, cb)
    if data.success then
        micReady = true
        DebugPrint('Mic captured successfully')
    else
        micReady = false
        isBroadcasting = false
        broadcastMode = nil
        broadcastFrequency = nil
        Notify('Mic capture failed: ' .. (data.error or 'unknown'), 'error')
        DebugPrint('Mic capture failed:', data.error)
    end
    cb('ok')
end)

RegisterNUICallback('signal', function(data, cb)
    TriggerServerEvent('cad-radiostation:webrtc:signal', data.targetPeerId, {
        type      = data.type,
        sdp       = data.sdp,
        candidate = data.candidate,
    })
    cb('ok')
end)

RegisterNUICallback('voiceConnected', function(data, cb)
    DebugPrint('Voice connected with peer:', data.peerId)
    cb('ok')
end)

RegisterNUICallback('audioError', function(data, cb)
    DebugPrint('Audio error:', data.error)
    cb('ok')
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(fromPeerId, signalData)
    NUI_ForwardSignal(fromPeerId, signalData)
end)

RegisterNetEvent('cad-radiostation:webrtc:createOffer', function(listenerId)
    if isBroadcasting and broadcastMode == 'voice' and micReady then
        NUI_CreateOffer(listenerId)
        DebugPrint('Creating offer for new listener:', listenerId)
    end
end)

RegisterNetEvent('cad-radiostation:webrtc:closePeer', function(peerId)
    NUI_ClosePeer(peerId)
end)

--- Tunes the player to a station by ID.
---@param stationId string The station ID to tune to
function TuneToStation(stationId)
    if currentStation and currentStation.stationId == stationId then
        Notify('Already tuned to this station', 'info')
        return
    end
    if currentStation then
        StopStream()
        NUI_CloseAll()
    end
    TriggerServerEvent('cad-radiostation:tuneStation', stationId)
end

--- Leaves the current station and stops all playback.
function LeaveStation()
    if not currentStation then return end

    StopStream()
    NUI_CloseAll()

    if isBroadcasting then
        TriggerServerEvent('cad-radiostation:stopBroadcast', broadcastFrequency)
        isBroadcasting = false
        broadcastMode = nil
        broadcastFrequency = nil
        micReady = false
    end

    TriggerServerEvent('cad-radiostation:leaveStation')
    currentStation = nil
    Notify('Radio turned off', 'info')
end

local function BuildVolumeValues()
    local values = {}
    for v = 0, 100, Config.VolumeStep do
        values[#values + 1] = tostring(v) .. '%'
    end
    return values
end

local function GetVolumeScrollIndex(volume)
    return math.floor(volume / Config.VolumeStep) + 1
end

local function VolumeFromScrollIndex(scrollIndex)
    return (scrollIndex - 1) * Config.VolumeStep
end

--- Opens the station detail menu for a specific station.
---@param station table The station config table
local function OpenStationMenu(station)
    local isCurrentStation = currentStation and currentStation.stationId == station.id
    local options = {}

    if isCurrentStation then
        options[#options + 1] = {
            label = '🎵 Currently Playing',
            icon  = 'circle-play',
            iconColor = '#4ade80',
            description = 'You are tuned to this station',
        }
    else
        options[#options + 1] = {
            label = 'Tune In',
            icon  = 'play',
            description = 'Start listening to this station',
            args  = { action = 'tune', stationId = station.id },
        }
    end

    options[#options + 1] = {
        label = 'Volume',
        icon  = 'volume-high',
        values = BuildVolumeValues(),
        defaultIndex = GetVolumeScrollIndex(currentVolume),
        close = false,
        args  = { action = 'volume' },
        description = 'Adjust radio volume',
    }

    if isCurrentStation then
        options[#options + 1] = {
            label = 'Turn Off',
            icon  = 'power-off',
            iconColor = '#ef4444',
            description = 'Stop listening',
            args  = { action = 'turnoff' },
        }
    end

    local canBroadcastStation = lib.callback.await('cad-radiostation:canBroadcast', false, station.frequency)

    if canBroadcastStation and activeBroadcastZones[station.frequency] then
        if isBroadcasting and broadcastFrequency == station.frequency then
            local modeLabel = broadcastMode == 'voice' and 'Voice' or 'URL'
            options[#options + 1] = {
                label = '🔴 Stop ' .. modeLabel .. ' Broadcast',
                icon  = 'microphone-slash',
                iconColor = '#ef4444',
                description = 'End your broadcast',
                args  = { action = 'stopbroadcast', frequency = station.frequency },
            }
        else
            options[#options + 1] = {
                label = '🎙️ Voice Broadcast',
                icon  = 'microphone',
                iconColor = '#3b82f6',
                description = 'Broadcast your voice via WebRTC',
                args  = { action = 'voicebroadcast', frequency = station.frequency, stationId = station.id },
            }
            options[#options + 1] = {
                label = '🔗 URL Broadcast',
                icon  = 'tower-broadcast',
                iconColor = '#f59e0b',
                description = 'Broadcast a stream URL to all listeners',
                args  = { action = 'urlbroadcast', frequency = station.frequency, stationId = station.id },
            }
        end
    end

    options[#options + 1] = {
        label = '← Back',
        icon  = 'arrow-left',
        args  = { action = 'back' },
    }

    lib.registerMenu({
        id = 'radio_station_' .. station.id,
        title = '📻 ' .. station.label .. ' (' .. station.frequency .. ' MHz)',
        position = 'top-right',
        onSideScroll = function(selected, scrollIndex, args)
            if args and args.action == 'volume' then
                currentVolume = VolumeFromScrollIndex(scrollIndex)
                SetStreamVolume(currentVolume)
                TriggerServerEvent('cad-radiostation:updateVolume', currentVolume)
            end
        end,
        onClose = function(keyPressed)
            if keyPressed == 'Backspace' then
                OpenRadioMenu()
            end
        end,
        options = options,
    }, function(selected, scrollIndex, args)
        if not args then return end

        if args.action == 'tune' then
            TuneToStation(args.stationId)
            Wait(300)
            OpenStationMenu(station)

        elseif args.action == 'turnoff' then
            LeaveStation()
            OpenRadioMenu()

        elseif args.action == 'volume' then
            currentVolume = VolumeFromScrollIndex(scrollIndex)
            SetStreamVolume(currentVolume)
            TriggerServerEvent('cad-radiostation:updateVolume', currentVolume)

        elseif args.action == 'voicebroadcast' then
            if not currentStation or currentStation.stationId ~= args.stationId then
                TuneToStation(args.stationId)
                Wait(500)
            end
            TriggerServerEvent('cad-radiostation:startVoiceBroadcast', args.frequency)
            Wait(300)
            OpenStationMenu(station)

        elseif args.action == 'urlbroadcast' then
            if not currentStation or currentStation.stationId ~= args.stationId then
                TuneToStation(args.stationId)
                Wait(500)
            end
            local input = lib.inputDialog('URL Broadcast', {
                {
                    type = 'input',
                    label = 'Stream URL',
                    description = 'Enter audio stream URL (.mp3, .ogg, Icecast/Shoutcast)',
                    placeholder = 'https://your-stream.com/live.mp3',
                    required = true,
                },
            })
            if input and input[1] and input[1] ~= '' then
                TriggerServerEvent('cad-radiostation:startUrlBroadcast', args.frequency, input[1])
                isBroadcasting = true
                broadcastMode = 'url'
                broadcastFrequency = args.frequency
            end
            Wait(300)
            OpenStationMenu(station)

        elseif args.action == 'stopbroadcast' then
            if broadcastMode == 'voice' then
                NUI_StopMic()
                micReady = false
            end
            TriggerServerEvent('cad-radiostation:stopBroadcast', args.frequency)
            isBroadcasting = false
            broadcastMode = nil
            broadcastFrequency = nil
            Wait(300)
            OpenStationMenu(station)

        elseif args.action == 'back' then
            OpenRadioMenu()
        end
    end)

    lib.showMenu('radio_station_' .. station.id)
end

--- Opens the main radio menu showing all available stations.
function OpenRadioMenu()
    if not IsInVehicle() and not inBroadcastingZone then
        Notify('You must be in a vehicle or a broadcasting zone to use the radio', 'error')
        return
    end

    -- Permission check moved to station detail menu

    local options = {}
    for i, station in ipairs(Config.Stations) do
        local isActive = currentStation and currentStation.stationId == station.id
        options[#options + 1] = {
            label = station.label .. (isActive and ' [PLAYING]' or ''),
            icon  = station.icon or 'radio',
            iconColor = isActive and '#4ade80' or '#94a3b8',
            description = station.description or ('Frequency: ' .. station.frequency .. ' MHz'),
            args = { action = 'openstation', index = i },
        }
    end

    if currentStation then
        options[#options + 1] = {
            label = '⏹ Turn Off Radio',
            icon  = 'power-off',
            iconColor = '#ef4444',
            description = 'Stop all radio playback',
            args = { action = 'turnoff' },
        }
    end

    lib.registerMenu({
        id = 'radio_main',
        title = '📻 Vehicle Radio',
        position = 'top-right',
        onClose = function() isMenuOpen = false end,
        options = options,
    }, function(selected, scrollIndex, args)
        if not args then return end
        if args.action == 'openstation' then
            local station = Config.Stations[args.index]
            if station then OpenStationMenu(station) end
        elseif args.action == 'turnoff' then
            LeaveStation()
        end
    end)

    isMenuOpen = true
    lib.showMenu('radio_main')
end

RegisterNetEvent('cad-radiostation:stationTuned', function(data)
    currentStation = {
        stationId      = data.stationId,
        label          = data.label,
        frequency      = data.frequency,
        streamUrl      = data.streamUrl,
        volume         = data.volume,
        isBroadcasting = data.isBroadcasting,
    }
    currentVolume = data.volume

    if data.streamUrl and data.streamUrl ~= '' then
        if not data.isBroadcasting or data.broadcastMode ~= 'voice' then
            PlayStream(data.streamUrl, data.volume)
        end
    end

    SendNUIMessage({ action = 'setLive', enabled = data.isBroadcasting == true })
    Notify('Tuned to ' .. data.label, 'success')
end)

RegisterNetEvent('cad-radiostation:stationLeft', function()
    currentStation = nil
    isBroadcasting = false
    broadcastMode = nil
    broadcastFrequency = nil
    micReady = false
    NUI_CloseAll()
    SendNUIMessage({ action = 'setLive', enabled = false })
end)

RegisterNetEvent('cad-radiostation:voiceBroadcastApproved', function(data)
    isBroadcasting = true
    broadcastMode = 'voice'
    broadcastFrequency = data.frequency

    StopStream()
    NUI_StartMic()
    SendNUIMessage({ action = 'setTransmit', enabled = false })

    CreateThread(function()
        local timeout = 30
        while not micReady and timeout > 0 do
            Wait(100)
            timeout = timeout - 1
        end

        if micReady then
            for _, listenerId in ipairs(data.listeners) do
                NUI_CreateOffer(listenerId)
                Wait(150)
            end
            DebugPrint('Sent offers to', #data.listeners, 'listeners')
        else
            DebugPrint('Mic not ready, cannot broadcast')
        end
    end)
end)

RegisterNetEvent('cad-radiostation:broadcastStarted', function(data)
    if currentStation and currentStation.frequency == data.frequency then
        if data.mode == 'voice' then
            Notify('Voice broadcast started!', 'success')
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true) -- Fixed type mismatch (true instead of 1)
            currentStation.isBroadcasting = true
            SendNUIMessage({ action = 'setLive', enabled = true })
            DebugPrint('Voice broadcast started, paused stream')
        end
    end
end)

RegisterNetEvent('cad-radiostation:broadcastStopped', function(data)
    if currentStation and currentStation.frequency == data.frequency then
        currentStation.isBroadcasting = false
        NUI_CloseAll()
        if data.streamUrl and data.streamUrl ~= '' then
            PlayStream(data.streamUrl, currentVolume)
        end
        SendNUIMessage({ action = 'setLive', enabled = false })
        DebugPrint('Broadcast stopped, resumed stream')
    end
end)

RegisterNetEvent('cad-radiostation:switchStream', function(data)
    if currentStation and currentStation.frequency == data.frequency then
        currentStation.isBroadcasting = data.isBroadcast
        currentStation.streamUrl = data.streamUrl
        if data.streamUrl and data.streamUrl ~= '' then
            PlayStream(data.streamUrl, currentVolume)
        end
        if data.isBroadcast then
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            Notify('Live broadcast incoming!', 'info')
        end
        SendNUIMessage({ action = 'setLive', enabled = data.isBroadcast == true })
    end
end)

RegisterCommand('openradio', function()
    local next = next
    if IsInVehicle() or next(activeBroadcastZones) ~= nil then
        OpenRadioMenu()
    else
        Notify('You must be in a vehicle or a broadcasting zone', 'error')
    end
end, false)

RegisterKeyMapping('openradio', Config.OpenKeyLabel or 'Open Vehicle Radio', 'keyboard', Config.OpenKey or 'F5')

if Config.StopOnExitVehicle then
    local wasInVehicle = false
    CreateThread(function()
        while true do
            local inVehicle = IsInVehicle()
            if wasInVehicle and not inVehicle and currentStation then
                LeaveStation()
                DebugPrint('Auto-stopped radio on exit')
            end
            wasInVehicle = inVehicle
            Wait(500)
        end
    end)
end

-- Initialize Station Zones and Targets
for _, station in ipairs(Config.Stations) do
    if station.zones then
        for _, zone in ipairs(station.zones) do
            lib.zones.box({
                coords = zone.coords,
                size = zone.size or vec3(4, 4, 4),
                rotation = zone.heading or 0.0,
                debug = zone.debug,
                onEnter = function()
                    activeBroadcastZones[station.frequency] = true
                    DebugPrint('Entered broadcasting zone for:', station.label)
                end,
                onExit = function()
                    activeBroadcastZones[station.frequency] = nil
                    DebugPrint('Exited broadcasting zone for:', station.label)
                    
                    if isBroadcasting and broadcastFrequency == station.frequency and not IsInVehicle() then
                        if broadcastMode == 'voice' then
                            NUI_StopMic()
                            micReady = false
                        end
                        TriggerServerEvent('cad-radiostation:stopBroadcast', broadcastFrequency)
                        isBroadcasting = false
                        broadcastMode = nil
                        broadcastFrequency = nil
                        Notify('Broadcast stopped: Left broadcasting zone', 'warning')
                    end
                end
            })
        end
    end

    if station.targets then
        for _, target in ipairs(station.targets) do
            if GetResourceState('ox_target') == 'started' then
                exports.ox_target:addSphereZone({
                    coords = target.coords,
                    radius = target.radius,
                    options = {
                        {
                            label = target.label,
                            icon = target.icon,
                            onSelect = function()
                                OpenStationMenu(station)
                            end,
                            canInteract = function()
                                return true
                            end
                        }
                    }
                })
            elseif GetResourceState('qb-target') == 'started' then
                exports['qb-target']:AddCircleZone(target.label, target.coords, target.radius, {
                    name = target.label,
                    debugPoly = false,
                }, {
                    options = {
                        {
                            label = target.label,
                            icon = target.icon,
                            action = function()
                                OpenStationMenu(station)
                            end,
                        },
                    },
                    distance = 2.0
                })
            end
        end
    end
end

-- Initialize PTT Keybind
lib.addKeybind({
    name = 'radio_ptt',
    description = 'Radio Push-to-Talk',
    defaultKey = Config.PTTKey or 'LMENU',
    onPressed = function()
        if isBroadcasting and broadcastMode == 'voice' then
            SendNUIMessage({ action = 'setTransmit', enabled = true })
        end
    end,
    onReleased = function()
        if isBroadcasting and broadcastMode == 'voice' then
            SendNUIMessage({ action = 'setTransmit', enabled = false })
        end
    end
})

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if currentStation then
        StopStream()
        NUI_CloseAll()
    end
end)
