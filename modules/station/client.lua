-- Station module client-side
-- Provides exports for other resources to interact with the radio

--- Export: Get current station info
exports('GetCurrentStation', function()
    return currentStation
end)

--- Export: Is player currently listening to radio
exports('IsListening', function()
    return currentStation ~= nil
end)

--- Export: Get current volume
exports('GetVolume', function()
    return currentVolume
end)

--- Export: Tune to station programmatically
exports('TuneToStation', function(stationId)
    TuneToStation(stationId)
end)

--- Export: Leave current station programmatically
exports('LeaveStation', function()
    LeaveStation()
end)

--- Export: Open the radio menu programmatically
exports('OpenRadioMenu', function()
    OpenRadioMenu()
end)
