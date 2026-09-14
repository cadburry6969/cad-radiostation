--- Client radio controller: tuning, volume, broadcasting and the two interfaces.
---@class RadioClient : OxClass
---@field private currentStation { stationId: string, label: string, frequency: number, streamUrl: string, isBroadcasting: boolean }|nil
---@field private currentVolume number
---@field private isBroadcasting boolean
---@field private broadcastMode BroadcastMode|nil
---@field private broadcastFrequency number|nil
---@field private micReady boolean
---@field private menuView 'radio'|'station'|nil
---@field private panelStationId string|nil Station shown by the station panel
local RadioClient = lib.class('RadioClient')

--- Initialises state at the configured default volume.
function RadioClient:constructor()
    self.currentStation = nil
    self.currentVolume = Config.defaultVolume
    self.isBroadcasting = false
    self.broadcastMode = nil
    self.broadcastFrequency = nil
    self.micReady = false
    self.menuView = nil
    self.panelStationId = nil
end

--- Whether the local player is seated in any vehicle.
---@return boolean
local function isInVehicle()
    return IsPedInAnyVehicle(PlayerPedId(), false)
end

--- Snapshot of the live radio state for the NUI.
---@return RadioState
function RadioClient:buildState()
    return {
        currentStationId   = self.currentStation and self.currentStation.stationId or nil,
        volume             = self.currentVolume,
        isBroadcasting     = self.isBroadcasting,
        broadcastMode      = self.broadcastMode,
        broadcastFrequency = self.broadcastFrequency,
    }
end

--- Static config values the NUI needs.
---@return NuiConfig
function RadioClient:buildConfig()
    return {
        volumeStep    = Config.volumeStep,
        defaultVolume = Config.defaultVolume,
        pttKeyLabel   = ClientConfig.pttKeyLabel,
    }
end

--- Pushes fresh state to whichever view is open.
function RadioClient:pushState()
    if not self.menuView then return end
    SendNUIMessage({ action = 'updateRadioState', state = self:buildState() })
end

--- Clears every local broadcast flag and releases the mic if it was held.
function RadioClient:resetBroadcastState()
    if self.broadcastMode == 'voice' then
        Audio:stopMic()
    end
    self.isBroadcasting = false
    self.broadcastMode = nil
    self.broadcastFrequency = nil
    self.micReady = false
end

--- Tunes the player to a station by id.
---@param stationId string
function RadioClient:tuneToStation(stationId)
    if self.currentStation and self.currentStation.stationId == stationId then return end

    if self.currentStation then
        Audio:stopStream()
        Audio:closeAll()
    end
    TriggerServerEvent('cad-radiostation:tuneStation', stationId)
end

--- Stops playback, ends any broadcast and leaves the current station.
function RadioClient:leaveStation()
    if not self.currentStation then return end

    Audio:stopStream()
    Audio:closeAll()

    if self.isBroadcasting and self.broadcastFrequency then
        TriggerServerEvent('cad-radiostation:stopBroadcast', self.broadcastFrequency)
    end
    self:resetBroadcastState()

    TriggerServerEvent('cad-radiostation:leaveStation')
    self.currentStation = nil
    Notify('Radio turned off', 'info')
    self:pushState()
end

--- The station the player is tuned to, or nil.
---@return table|nil
function RadioClient:getCurrentStation()
    return self.currentStation
end

--- Current listening volume, 0-100.
---@return number
function RadioClient:getVolume()
    return self.currentVolume
end

--- Frequency the player is broadcasting on, or nil.
---@return number|nil
function RadioClient:getBroadcastFrequency()
    return self.broadcastFrequency
end

--- Closes whichever view is open and releases NUI focus.
function RadioClient:closeMenu()
    if not self.menuView then return end
    self.menuView = nil
    self.panelStationId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

--- Opens the listen-only vehicle radio, which requires being in a vehicle.
function RadioClient:openVehicleRadio()
    if self.menuView == 'radio' then
        self:closeMenu()
        return
    end

    if not isInVehicle() then
        Notify('You must be in a vehicle to use the radio', 'error')
        return
    end

    self.menuView = 'radio'
    self.panelStationId = nil
    SendNUIMessage({
        action   = 'openRadio',
        stations = Stations:getAll(),
        state    = self:buildState(),
        config   = self:buildConfig(),
    })
    SetNuiFocus(true, true)
end

--- Opens the broadcast panel for a single station, usable on foot.
--- The caller is responsible for the zone or target proximity check.
---@param stationId string
function RadioClient:openStationPanel(stationId)
    if self.menuView == 'station' and self.panelStationId == stationId then
        self:closeMenu()
        return
    end

    local station = Stations:getById(stationId)
    if not station then
        Notify('Station not found', 'error')
        return
    end

    if not station.canBroadcast then
        Notify('You are not authorised to operate this station', 'error')
        return
    end

    local broadcastState = lib.callback.await('cad-radiostation:getBroadcastState', false, station.frequency)

    self.menuView = 'station'
    self.panelStationId = stationId
    SendNUIMessage({
        action         = 'openStation',
        station        = station,
        state          = self:buildState(),
        config         = self:buildConfig(),
        broadcastState = broadcastState,
    })
    SetNuiFocus(true, true)
end

--- Opens whichever interface fits the player's situation.
function RadioClient:openContextual()
    if self.menuView then
        self:closeMenu()
        return
    end

    if isInVehicle() then
        self:openVehicleRadio()
        return
    end

    local zoneStation = Stations:getCurrentZoneStation()
    if zoneStation then
        self:openStationPanel(zoneStation.id)
        return
    end

    Notify('You must be in a vehicle or an authorised broadcast zone', 'error')
end

--- Stops an in-progress broadcast, for example when the host leaves the zone.
---@param reason string|nil Message shown to the host
function RadioClient:stopBroadcast(reason)
    if not self.isBroadcasting or not self.broadcastFrequency then return end

    TriggerServerEvent('cad-radiostation:stopBroadcast', self.broadcastFrequency)
    self:resetBroadcastState()
    if reason then Notify(reason, 'warning') end
    self:pushState()
end

--- Marks the mic as captured and starts offering to listeners, or aborts on failure.
---@param success boolean
---@param err string|nil
function RadioClient:onMicCaptured(success, err)
    if success then
        self.micReady = true
        Debug('mic captured')
    else
        self.micReady = false
        self:resetBroadcastState()
        Notify('Mic capture failed: ' .. (err or 'unknown'), 'error')
        self:pushState()
    end
end

--- Applies a confirmed tune-in from the server and begins playback.
---@param data table
function RadioClient:onStationTuned(data)
    self.currentStation = {
        stationId      = data.stationId,
        label          = data.label,
        frequency      = data.frequency,
        streamUrl      = data.streamUrl,
        isBroadcasting = data.isBroadcasting,
    }
    self.currentVolume = data.volume

    -- A live voice broadcast replaces the stream, so do not start it as well
    if not (data.isBroadcasting and data.broadcastMode == 'voice') then
        Audio:playStream(data.streamUrl, data.volume)
    end

    Audio:setLive(data.isBroadcasting == true)
    Notify('Tuned to ' .. data.label, 'success')
    self:pushState()
end

--- Clears playback after the server removes the player from a station.
function RadioClient:onStationLeft()
    self.currentStation = nil
    Audio:stopStream()
    Audio:closeAll()
    Audio:setLive(false)
    self:resetBroadcastState()
    self:pushState()
end

--- Arms the mic and offers to every current listener once the broadcast is approved.
---@param data { frequency: number, listeners: number[] }
function RadioClient:onVoiceApproved(data)
    self.isBroadcasting = true
    self.broadcastMode = 'voice'
    self.broadcastFrequency = data.frequency

    Audio:stopStream()
    -- Transmit is armed off first so the mic opens muted behind push-to-talk
    Audio:setTransmit(false)
    Audio:startMic()
    self:pushState()

    CreateThread(function()
        -- Wait for the `micCaptured` callback before offering to listeners
        local attempts = 30
        while not self.micReady and attempts > 0 do
            Wait(100)
            attempts = attempts - 1
        end

        if not self.micReady then
            Debug('mic not ready, aborting broadcast')
            return
        end

        for _, listenerId in ipairs(data.listeners) do
            Audio:createOffer(listenerId)
            Wait(150)
        end
        Debug(('sent offers to %d listeners'):format(#data.listeners))
    end)
end

--- Handles a voice broadcast starting on the listener's own frequency.
---@param data { frequency: number, mode: BroadcastMode }
function RadioClient:onBroadcastStarted(data)
    if self.currentStation and self.currentStation.frequency == data.frequency and data.mode == 'voice' then
        self.currentStation.isBroadcasting = true
        Audio:stopStream()
        Audio:setLive(true)
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        Notify('Live broadcast incoming!', 'info')
    end
    self:pushState()
end

--- Resumes the default stream once a voice broadcast ends.
---@param data { frequency: number, streamUrl: string }
function RadioClient:onBroadcastStopped(data)
    if self.currentStation and self.currentStation.frequency == data.frequency then
        self.currentStation.isBroadcasting = false
        Audio:closeAll()
        Audio:playStream(data.streamUrl, self.currentVolume)
        Audio:setLive(false)
    end
    self:pushState()
end

--- Switches the active URL for the player's frequency.
---@param data { frequency: number, streamUrl: string, isBroadcast: boolean }
function RadioClient:onSwitchStream(data)
    if self.currentStation and self.currentStation.frequency == data.frequency then
        self.currentStation.isBroadcasting = data.isBroadcast
        self.currentStation.streamUrl = data.streamUrl
        Audio:playStream(data.streamUrl, self.currentVolume)

        if data.isBroadcast then
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            Notify('Live broadcast incoming!', 'info')
        end
        Audio:setLive(data.isBroadcast == true)
    end
    self:pushState()
end

--- Sets the listening volume and persists it server-side.
---@param volume number
function RadioClient:setVolume(volume)
    self.currentVolume = math.max(0, math.min(100, math.floor(volume)))
    Audio:setVolume(self.currentVolume)
    TriggerServerEvent('cad-radiostation:updateVolume', self.currentVolume)
end

--- Records a locally-started URL broadcast and mirrors it to the NUI.
---@param frequency number
function RadioClient:beginUrlBroadcast(frequency)
    self.isBroadcasting = true
    self.broadcastMode = 'url'
    self.broadcastFrequency = frequency
    self:pushState()
end

--- Whether a voice broadcast is currently live from this client.
---@return boolean
function RadioClient:isVoiceBroadcasting()
    return self.isBroadcasting and self.broadcastMode == 'voice'
end

--- Whether any broadcast (voice or URL) is currently live from this client.
---@return boolean
function RadioClient:isLiveBroadcaster()
    return self.isBroadcasting
end

--- Whether a captured mic is ready to offer to listeners.
---@return boolean
function RadioClient:isMicReady()
    return self.micReady
end

--- Whether the player is currently tuned to any station.
---@return boolean
function RadioClient:hasStation()
    return self.currentStation ~= nil
end

--- Singleton controller shared by the client modules.
Radio = RadioClient:new()

RegisterNUICallback('closeMenu', function(_, cb)
    Radio:closeMenu()
    cb('ok')
end)

RegisterNUICallback('tuneStation', function(data, cb)
    if data and data.stationId then Radio:tuneToStation(data.stationId) end
    cb('ok')
end)

RegisterNUICallback('leaveStation', function(_, cb)
    Radio:leaveStation()
    cb('ok')
end)

RegisterNUICallback('setVolume', function(data, cb)
    local volume = tonumber(data and data.volume)
    if volume then Radio:setVolume(volume) end
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
        Radio:beginUrlBroadcast(data.frequency)
    end
    cb('ok')
end)

RegisterNUICallback('stopBroadcast', function(data, cb)
    local frequency = (data and data.frequency) or Radio:getBroadcastFrequency()
    if frequency then
        TriggerServerEvent('cad-radiostation:stopBroadcast', frequency)
    end
    Radio:resetBroadcastState()
    Radio:pushState()
    cb('ok')
end)

RegisterNUICallback('micCaptured', function(data, cb)
    Radio:onMicCaptured(data.success, data.error)
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
    Radio:onStationTuned(data)
end)

RegisterNetEvent('cad-radiostation:stationLeft', function()
    Radio:onStationLeft()
end)

RegisterNetEvent('cad-radiostation:voiceBroadcastApproved', function(data)
    Radio:onVoiceApproved(data)
end)

RegisterNetEvent('cad-radiostation:broadcastStarted', function(data)
    Radio:onBroadcastStarted(data)
end)

RegisterNetEvent('cad-radiostation:broadcastStopped', function(data)
    Radio:onBroadcastStopped(data)
end)

RegisterNetEvent('cad-radiostation:switchStream', function(data)
    Radio:onSwitchStream(data)
end)

RegisterNetEvent('cad-radiostation:webrtc:signal', function(fromPeerId, signalData)
    Audio:forwardSignal(fromPeerId, signalData)
end)

RegisterNetEvent('cad-radiostation:webrtc:createOffer', function(listenerId)
    if Radio:isVoiceBroadcasting() and Radio:isMicReady() then
        Audio:createOffer(listenerId)
    end
end)

RegisterNetEvent('cad-radiostation:webrtc:closePeer', function(peerId)
    Audio:closePeer(peerId)
end)

RegisterCommand('openradio', function()
    Radio:openContextual()
end, false)

RegisterKeyMapping('openradio', ClientConfig.openKeyLabel, 'keyboard', ClientConfig.openKey)

lib.addKeybind({
    name = 'radio_ptt',
    description = 'Radio Push-to-Talk',
    defaultKey = ClientConfig.pttKey,
    onPressed = function()
        if Radio:isVoiceBroadcasting() then Audio:setTransmit(true) end
    end,
    onReleased = function()
        if Radio:isVoiceBroadcasting() then Audio:setTransmit(false) end
    end,
})

if ClientConfig.stopOnExitVehicle then
    CreateThread(function()
        local wasInVehicle = false
        while true do
            local inVehicle = isInVehicle()
            -- Only vehicle listening stops here, a zone host on foot keeps playing
            if wasInVehicle and not inVehicle and Radio:hasStation() and not Radio:isLiveBroadcaster()
                and not Stations:isInAnyZone() then
                Radio:leaveStation()
                Debug('auto-stopped radio on vehicle exit')
            end
            wasInVehicle = inVehicle
            Wait(500)
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Audio:stopStream()
    Audio:closeAll()
    SetNuiFocus(false, false)
end)
