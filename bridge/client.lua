Config = lib.load('config.shared')
ClientConfig = lib.load('config.client')

--- Shows a notification through whichever framework is running.
---@param msg string
---@param type string|nil 'success' | 'error' | 'info' | 'warning'
function Notify(msg, type)
    if GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', msg)
    elseif GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') == 'started' then
        TriggerEvent('QBCore:Notify', msg, type)
    else
        lib.notify({ description = msg, type = type })
    end
end

--- Prints a namespaced message when debug logging is enabled.
function Debug(...)
    if Config.debug then
        print('[cad-radiostation:client]', ...)
    end
end

--- Listens to playerLoad and initialises stations (ESX)
RegisterNetEvent('esx:playerLoaded', function()
    TriggerServerEvent('cad-radiostation:requestStations')
end)

--- Listens to playerLoad and initialises stations (QB/QBOX)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('cad-radiostation:requestStations')
end)