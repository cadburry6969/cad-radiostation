-- Station module server-side
-- Handles station-level metadata and exports for other resources

--- Export: Get all available stations
exports('GetStations', function()
    return Config.Stations
end)

--- Export: Get station by ID
exports('GetStationById', function(stationId)
    for _, station in ipairs(Config.Stations) do
        if station.id == stationId then
            return station
        end
    end
    return nil
end)

--- Export: Get station by frequency
exports('GetStationByFrequency', function(frequency)
    for _, station in ipairs(Config.Stations) do
        if station.frequency == frequency then
            return station
        end
    end
    return nil
end)
