function Notify(msg, type)
    if GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', msg)
    elseif GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') == 'started' then
        TriggerEvent('QBCore:Notify', msg, type)
    else
        lib.notify({ description = msg, type = type })
    end
end

function GetPlate(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    return GetVehicleNumberPlateText(vehicle):gsub('^%s*(.-)%s*$', '%1')
end
