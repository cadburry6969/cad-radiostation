---@class RadioClient
Radio = {}

---@type { stationId: string, label: string, frequency: number, streamUrl: string, isBroadcasting: boolean }|nil
local currentStation = nil
local currentVolume = Config.defaultVolume

local isBroadcasting = false
---@type BroadcastMode|nil
local broadcastMode = nil
---@type number|nil
local broadcastFrequency = nil
local micReady = false

---@type 'radio'|'station'|nil
local menuView = nil
---@type string|nil Station shown by the station panel
local panelStationId = nil

--- Whether the local player is seated in any vehicle.
---@return boolean
local function isInVehicle()
    return IsPedInAnyVehicle(PlayerPedId(), false)
end

--- Snapshot of the live radio state for the NUI.
---@return RadioState
local function buildState()
    return {
        currentStationId   = currentStation and currentStation.stationId or nil,
        volume             = currentVolume,
        isBroadcasting     = isBroadcasting,
        broadcastMode      = broadcastMode,
        broadcastFrequency = broadcastFrequency,
    }
end

--- Static config values the NUI needs.
---@return NuiConfig
local function buildConfig()
    return {
        volumeStep    = Config.volumeStep,
        defaultVolume = Config.defaultVolume,
        pttKeyLabel   = ClientConfig.pttKeyLabel,
    }
end

--- Pushes fresh state to whichever view is open.
local function pushState()
    if not menuView then return end
    SendNUIMessage({ action = 'updateRadioState', state = buildState() })
end

--- Clears every local broadcast flag and releases the mic if it was held.
local function resetBroadcastState()
    if broadcastMode == 'voice' then
        Audio.StopMic()
    end
    isBroadcasting = false
    broadcastMode = nil
    broadcastFrequency = nil
    micReady = false
end

--- Tunes the player to a station by id.
---@param stationId string
function Radio.TuneToStation(stationId)
    if currentStation and currentStation.stationId == stationId then return end

    if currentStation then
        Audio.StopStream()
        Audio.CloseAll()
    end
    TriggerServerEvent('cad-radiostation:tuneStation', stationId)
end

--- Stops playback, ends any broadcast and leaves the current station.
function Radio.LeaveStation()
    if not currentStation then return end

    Audio.StopStream()
    Audio.CloseAll()

    if isBroadcasting and broadcastFrequency then
        TriggerServerEvent('cad-radiostation:stopBroadcast', broadcastFrequency)
    end
    resetBroadcastState()

    TriggerServerEvent('cad-radiostation:leaveStation')
    currentStation = nil
    Notify('Radio turned off', 'info')
    pushState()
end

--- The station the player is tuned to, or nil.
---@return table|nil
function Radio.GetCurrentStation()
    return currentStation
end

--- Current listening volume, 0-100.
---@return number
function Radio.GetVolume()
    return currentVolume
end

--- Frequency the player is broadcasting on, or nil.
---@return number|nil
function Radio.GetBroadcastFrequency()
    return broadcastFrequency
end

--- Closes whichever view is open and releases NUI focus.
function Radio.CloseMenu()
    if not menuView then return end
    menuView = nil
    panelStationId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

--- Opens the listen-only vehicle radio, which requires being in a vehicle.
function Radio.OpenVehicleRadio()
    if menuView == 'radio' then
        Radio.CloseMenu()
        return
    end

    if not isInVehicle() then
        Notify('You must be in a vehicle to use the radio', 'error')
        return
    end

    menuView = 'radio'
    panelStationId = nil
    SendNUIMessage({
        action   = 'openRadio',
        stations = Stations.GetAll(),
        state    = buildState(),
        config   = buildConfig(),
    })
    SetNuiFocus(true, true)
end

--- Opens the broadcast panel for a single station, usable on foot.
--- The caller is responsible for the zone or target proximity check.
---@param stationId string
function Radio.OpenStationPanel(stationId)
    if menuView == 'station' and panelStationId == stationId then
        Radio.CloseMenu()
        return
    end

    local station = Stations.GetById(stationId)
    if not station then
        Notify('Station not found', 'error')
        return
    end

    if not station.canBroadcast then
        Notify('You are not authorised to operate this station', 'error')
        return
    end

    local broadcastState = lib.callback.await('cad-radiostation:getBroadcastState', false, station.frequency)

    menuView = 'station'
    panelStationId = stationId
    SendNUIMessage({
        action         = 'openStation',
        station        = station,
        state          = buildState(),
        config         = buildConfig(),
        broadcastState = broadcastState,
    })
    SetNuiFocus(true, true)
end

--- Opens whichever interface fits the player's situation.
function Radio.OpenContextual()
    if menuView then
        Radio.CloseMenu()
        return
    end

    if isInVehicle() then
        Radio.OpenVehicleRadio()
        return
    end

    local zoneStation = Stations.GetCurrentZoneStation()
    if zoneStation then
        Radio.OpenStationPanel(zoneStation.id)
        return
    end

    Notify('You must be in a vehicle or an authorised broadcast zone', 'error')
end

--- Stops an in-progress broadcast, for example when the host leaves the zone.
---@param reason string|nil Message shown to the host
function Radio.StopBroadcast(reason)
    if not isBroadcasting or not broadcastFrequency then return end

    TriggerServerEvent('cad-radiostation:stopBroadcast', broadcastFrequency)
    resetBroadcastState()
    if reason then Notify(reason, 'warning') end
    pushState()
end

RegisterNUICallback('closeMenu', function(_, cb)
    menuView = nil
    panelStationId = nil
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('tuneStation', function(data, cb)
    if data and data.stationId then Radio.TuneToStation(data.stationId) end
    cb('ok')
end)

RegisterNUICallback('leaveStation', function(_, cb)
    Radio.LeaveStation()
    cb('ok')
end)

RegisterNUICallback('setVolume', function(data, cb)
    local volume = tonumber(data and data.volume)
    if volume then
        currentVolume = math.max(0, math.min(100, math.floor(volume)))
        Audio.SetVolume(currentVolume)
        TriggerServerEvent('cad-radiostation:updateVolume', currentVolume)
    end
    cb('ok')
end)

RegisterNUICallback('startVoiceBroadcast', function(data, cb)
    if data and data.frequency then
        TriggerServerEvent('cad-radiostation:startVoiceBroadcast', data.frequency)
    end
    cb('ok')
end)

RegisterNUICallback('startUrlBroadcast', function(data, cb)
    if data and data.frequency and type(data.url) == 'string' and data.url ~= '' then
        TriggerServerEvent('cad-radiostation:startUrlBroadcast', data.frequency, data.url)
        isBroadcasting = true
        broadcastMode = 'url'
        broadcastFrequency = data.frequency
        pushState()
    end
    cb('ok')
end)

RegisterNUICallback('stopBroadcast', function(data, cb)
    local frequency = (data and data.frequency) or broadcastFrequency
    if frequency then
        TriggerServerEvent('cad-radiostation:stopBroadcast', frequency)
    end
    resetBroadcastState()
    pushState()
    cb('ok')
end)

RegisterNUICallback('micCaptured', function(data, cb)
    if data.success then
        micReady = true
        Debug('mic captured')
    else
        micReady = false
        resetBroadcastState()
        Notify('Mic capture failed: ' .. (data.error or 'unknown'), 'error')
        pushState()
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
    Debug('voice connected with peer', data.peerId)
    cb('ok')
end)

RegisterNUICallback('audioError', function(data, cb)
    Debug('audio error:', data.error)
    cb('ok')
end)

RegisterNetEvent('cad-radiostation:stationTuned', function(data)
    currentStation = {
        stationId      = data.stationId,
        label          = data.label,
        frequency      = data.frequency,
        streamUrl      = data.streamUrl,
        isBroadcasting = data.isBroadcasting,
    }
    currentVolume = data.volume

    -- A live voice broadcast replaces the stream, so do not start it as well
    if not (data.isBroadcasting and data.broadcastMode == 'voice') then
        Audio.PlayStream(data.streamUrl, data.volume)
    end

    Audio.SetLive(data.isBroadcasting == true)
    Notify('Tuned to ' .. data.label, 'success')
    pushState()
end)

RegisterNetEvent('cad-radiostation:stationLeft', function()
    currentStation = nil
    Audio.StopStream()
    Audio.CloseAll()
    Audio.SetLive(false)
    resetBroadcastState()
    pushState()
end)

RegisterNetEvent('cad-radiostation:voiceBroadcastApproved', function(data)
    isBroadcasting = true
    broadcastMode = 'voice'
    broadcastFrequency = data.frequency

    Audio.StopStream()
    -- Transmit is armed off first so the mic opens muted behind push-to-talk
    Audio.SetTransmit(false)
    Audio.StartMic()
    pushState()

    CreateThread(function()
        -- Wait for the `micCaptured` callback before offering to listeners
        local attempts = 30
        while not micReady and attempts > 0 do
            Wait(100)
            attempts = attempts - 1
        end

        if not micReady then
            Debug('mic not ready, aborting broadcast')
            return
        end

        for _, listenerId in ipairs(data.listeners) do
            Audio.CreateOffer(listenerId)
            Wait(150)
        end
        Debug(('sent offers to %d listeners'):format(#data.listeners))
    end)
end)

RegisterNetEvent('cad-radiostation:broadcastStarted', function(data)
    if currentStation and currentStation.frequency == data.frequency and data.mode == 'voice' then
        currentStation.isBroadcasting = true
        Audio.StopStream()
        Audio.SetLive(true)
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        Notify('Live broadcast incoming!', 'info')
    end
    pushState()
end)

RegisterNetEvent('cad-radiostation:broadcastStopped', function(data)
    if currentStation and currentStation.frequency == data.frequency then
        currentStation.isBroadcasting = false
        Audio.CloseAll()
        Audio.PlayStream(data.streamUrl, currentVolume)
        Audio.SetLive(false)
    end
    pushState()
end)

RegisterNetEvent('cad-radiostation:switchStream', function(data)
    if currentStation and currentStation.frequency == data.frequency then
        currentStation.isBroadcasting = data.isBroadcast
        currentStation.streamUrl = data.streamUrl
        Audio.PlayStream(data.streamUrl, currentVolume)

        if data.isBroadcast then
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            Notify('Live broadcast incoming!', 'info')
        end
        Audio.SetLive(data.isBroadcast == true)
    end
    pushState()
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(fromPeerId, signalData)
    Audio.ForwardSignal(fromPeerId, signalData)
end)

RegisterNetEvent('cad-radiostation:webrtc:createOffer', function(listenerId)
    if isBroadcasting and broadcastMode == 'voice' and micReady then
        Audio.CreateOffer(listenerId)
    end
end)

RegisterNetEvent('cad-radiostation:webrtc:closePeer', function(peerId)
    Audio.ClosePeer(peerId)
end)

RegisterCommand('openradio', function()
    Radio.OpenContextual()
end, false)

RegisterKeyMapping('openradio', ClientConfig.openKeyLabel, 'keyboard', ClientConfig.openKey)

lib.addKeybind({
    name = 'radio_ptt',
    description = 'Radio Push-to-Talk',
    defaultKey = ClientConfig.pttKey,
    onPressed = function()
        if isBroadcasting and broadcastMode == 'voice' then
            Audio.SetTransmit(true)
        end
    end,
    onReleased = function()
        if isBroadcasting and broadcastMode == 'voice' then
            Audio.SetTransmit(false)
        end
    end,
})

if ClientConfig.stopOnExitVehicle then
    CreateThread(function()
        local wasInVehicle = false
        while true do
            local inVehicle = isInVehicle()
            -- Only vehicle listening stops here, a zone host on foot keeps playing
            if wasInVehicle and not inVehicle and currentStation and not isBroadcasting
                and not Stations.IsInAnyZone() then
                Radio.LeaveStation()
                Debug('auto-stopped radio on vehicle exit')
            end
            wasInVehicle = inVehicle
            Wait(500)
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Audio.StopStream()
    Audio.CloseAll()
    SetNuiFocus(false, false)
end)
