function GetPlayer(source)
    local player = {}

    if GetResourceState('es_extended') == 'started' then
        local xPlayer = exports['es_extended']:getSharedObject().GetPlayerFromId(source)
        if not xPlayer then return nil end
        player.identifier = xPlayer.getIdentifier()
        player.job = xPlayer.getJob().name
        player.group = xPlayer.getGroup()
    elseif GetResourceState('qbx_core') == 'missing' and GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if not xPlayer then return nil end
        player.identifier = xPlayer.PlayerData.citizenid
        player.job = xPlayer.PlayerData.job.name
        player.group = QBCore.Functions.GetPermission(source)
    elseif GetResourceState('qbx_core') == 'started' then
        local xPlayer = exports.qbx_core:GetPlayer(source)
        if not xPlayer then return nil end
        player.identifier = xPlayer.PlayerData.citizenid
        player.job = xPlayer.PlayerData.job.name
        player.group = exports.qbx_core:GetPermission(source)
    else
        player.identifier = GetPlayerIdentifier(source, 0)
        player.job = 'none'
        player.group = IsPlayerAceAllowed(source, 'admin') and 'admin' or 'user'
    end

    return player
end

function HasPermission(source, permission)
    return true
end

function Notify(source, msg, type)
    if GetResourceState('ox_lib') == 'started' then
        TriggerClientEvent('ox_lib:notify', source, { description = msg, type = type })
    elseif GetResourceState('es_extended') == 'started' then
        TriggerClientEvent('esx:showNotification', source, msg)
    elseif GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') == 'started' then
        TriggerClientEvent('QBCore:Notify', source, msg, type)
    end
end