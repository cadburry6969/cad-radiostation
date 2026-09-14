--- Thin bridge that drives the NUI audio + WebRTC layer via NUI messages.
---@class AudioBridge : OxClass
local AudioBridge = lib.class('AudioBridge')

--- Starts playback of a media URL in the NUI.
---@param url string
---@param volume number Volume 0-100
function AudioBridge:playStream(url, volume)
    if not url or url == '' then return end
    SendNUIMessage({ action = 'playStream', url = url, volume = volume / 100 })
    Debug('playing stream', url)
end

--- Stops any media currently playing.
function AudioBridge:stopStream()
    SendNUIMessage({ action = 'stopStream' })
end

--- Sets the playback volume (0-100).
---@param volume number
function AudioBridge:setVolume(volume)
    SendNUIMessage({ action = 'setVolume', volume = volume / 100 })
end

--- Toggles the on-screen LIVE indicator.
---@param enabled boolean
function AudioBridge:setLive(enabled)
    SendNUIMessage({ action = 'setLive', enabled = enabled })
end

--- Mutes or unmutes the outgoing mic track, driving the push-to-talk indicator.
---@param enabled boolean
function AudioBridge:setTransmit(enabled)
    SendNUIMessage({ action = 'setTransmit', enabled = enabled })
end

--- Asks the NUI for microphone access, answered by the `micCaptured` callback.
function AudioBridge:startMic()
    SendNUIMessage({ action = 'startMic' })
end

--- Releases the microphone and tears down every peer connection.
function AudioBridge:stopMic()
    SendNUIMessage({ action = 'stopMic' })
end

--- Creates a WebRTC offer for a listener that just tuned in.
---@param listenerId number Server ID of the listener
function AudioBridge:createOffer(listenerId)
    SendNUIMessage({ action = 'createOffer', listenerId = listenerId })
end

--- Closes the peer connection with a single peer.
---@param peerId number Server ID of the peer
function AudioBridge:closePeer(peerId)
    SendNUIMessage({ action = 'closePeer', peerId = peerId })
end

--- Closes every peer connection and releases the mic if held.
function AudioBridge:closeAll()
    SendNUIMessage({ action = 'closeAll' })
end

--- Forwards an incoming WebRTC signal to the NUI peer layer.
---@param fromPeerId number Server ID of the sending peer
---@param signalData table Signal payload with `type`, and `sdp` or `candidate`
function AudioBridge:forwardSignal(fromPeerId, signalData)
    SendNUIMessage({
        action     = 'signal',
        fromPeerId = fromPeerId,
        signalType = signalData.type,
        sdp        = signalData.sdp,
        candidate  = signalData.candidate,
    })
end

--- Singleton bridge shared by the client modules.
Audio = AudioBridge:new()
