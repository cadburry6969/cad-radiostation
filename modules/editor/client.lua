local MENU_MAIN    = 'cad_radio_editor_main'
local MENU_STATION = 'cad_radio_editor_station'
local MENU_ZONES   = 'cad_radio_editor_zones'
local MENU_TARGETS = 'cad_radio_editor_targets'

---@type Station|nil Station currently being edited
local draft = nil

---@type string|nil Id the draft had when it was opened, nil when creating
local draftOriginalId = nil

local registerStationMenu, showStationMenu, showMainMenu

--- Returns an empty station draft.
---@return Station
local function newDraft()
    return {
        id          = '',
        label       = '',
        frequency   = 0,
        streamUrl   = '',
        icon        = 'radio',
        description = '',
        hostJobs    = {},
        zones       = {},
        targets     = {},
    }
end

--- Splits a comma separated list into trimmed, non-empty entries.
---@param value string|nil
---@return string[]
local function splitList(value)
    local result = {}
    for entry in tostring(value or ''):gmatch('[^,]+') do
        local trimmed = entry:match('^%s*(.-)%s*$')
        if trimmed ~= '' then result[#result + 1] = trimmed end
    end
    return result
end

--- Converts camera rotation into a unit direction vector.
---@param rotation vector3
---@return vector3
local function rotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local absX = math.abs(math.cos(x))
    return vec3(-math.sin(z) * absX, math.cos(z) * absX, math.sin(x))
end

--- Casts a ray from the camera and returns where it lands.
---@return vector3 coords, boolean hit
local function raycastFromCamera()
    local camCoords = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local destination = camCoords + direction * ClientConfig.raycastDistance

    local handle = StartShapeTestRay(
        camCoords.x, camCoords.y, camCoords.z,
        destination.x, destination.y, destination.z,
        -1, PlayerPedId(), 0
    )
    local _, hit, endCoords = GetShapeTestResult(handle)

    if hit == 1 then return endCoords, true end
    return destination, false
end

--- Interactive point picker: aim with the camera, confirm with ENTER.
---@return vector3|nil coords Nil when cancelled
local function pickCoords()
    lib.showTextUI('[ENTER] Confirm point  •  [BACKSPACE] Cancel')

    local picked = nil
    while true do
        Wait(0)
        local coords, hit = raycastFromCamera()

        DrawMarker(28, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2,
            hit and 60 or 200, hit and 200 or 60, 90, 120, false, false, 2, false, nil, nil, false)

        if IsControlJustPressed(0, 191) then
            picked = coords
            break
        end
        if IsControlJustPressed(0, 194) then break end
    end

    lib.hideTextUI()
    return picked
end

--- Draws the outline of a box rotated around its Z axis.
---@param centre vector3
---@param size vector3
---@param heading number
local function drawBoxOutline(centre, size, heading)
    local rad = math.rad(heading)
    local cos, sin = math.cos(rad), math.sin(rad)
    local hx, hy, hz = size.x / 2, size.y / 2, size.z / 2

    -- Corner offsets in local space, rotated into world space
    local corners = {}
    local offsets = { { -hx, -hy }, { hx, -hy }, { hx, hy }, { -hx, hy } }
    for index, offset in ipairs(offsets) do
        local x, y = offset[1], offset[2]
        corners[index] = vec3(centre.x + x * cos - y * sin, centre.y + x * sin + y * cos, centre.z)
    end

    for index = 1, 4 do
        local a, b = corners[index], corners[index % 4 + 1]
        DrawLine(a.x, a.y, a.z - hz, b.x, b.y, b.z - hz, 60, 200, 90, 200)
        DrawLine(a.x, a.y, a.z + hz, b.x, b.y, b.z + hz, 60, 200, 90, 200)
        DrawLine(a.x, a.y, a.z - hz, a.x, a.y, a.z + hz, 60, 200, 90, 200)
    end
end

--- Interactive box builder: the box follows the player and the keys resize it.
---@param existing StationZone|nil Zone to re-place, or nil for a new one
---@return StationZone|nil zone Nil when cancelled
local function placeBox(existing)
    local size = existing and vec3(existing.size.x, existing.size.y, existing.size.z) or vec3(4.0, 4.0, 3.0)
    local heading = existing and existing.heading or 0.0
    local confirmed = false

    lib.showTextUI(table.concat({
        '**Place broadcast zone**  ',
        'Walk to position the box  ',
        '[ARROWS] Length / width  ',
        '[PAGE UP / DOWN] Height  ',
        '[,] / [.] Rotate  ',
        '[ENTER] Confirm  •  [BACKSPACE] Cancel',
    }, '\n'))

    local centre
    while true do
        Wait(0)
        local coords = GetEntityCoords(PlayerPedId())
        centre = vec3(coords.x, coords.y, coords.z + size.z / 2 - 1.0)

        drawBoxOutline(centre, size, heading)

        if IsControlPressed(0, 172) then size = vec3(size.x, size.y + 0.05, size.z) end
        if IsControlPressed(0, 173) then size = vec3(size.x, math.max(0.5, size.y - 0.05), size.z) end
        if IsControlPressed(0, 175) then size = vec3(size.x + 0.05, size.y, size.z) end
        if IsControlPressed(0, 174) then size = vec3(math.max(0.5, size.x - 0.05), size.y, size.z) end
        if IsControlPressed(0, 10) then size = vec3(size.x, size.y, size.z + 0.05) end
        if IsControlPressed(0, 11) then size = vec3(size.x, size.y, math.max(0.5, size.z - 0.05)) end
        if IsControlPressed(0, 82) then heading = (heading + 1.0) % 360 end
        if IsControlPressed(0, 81) then heading = (heading - 1.0) % 360 end

        if IsControlJustPressed(0, 191) then
            confirmed = true
            break
        end
        if IsControlJustPressed(0, 194) then break end
    end

    lib.hideTextUI()
    if not confirmed then return nil end

    return {
        coords  = { x = centre.x, y = centre.y, z = centre.z },
        size    = { x = size.x, y = size.y, z = size.z },
        heading = heading,
    }
end

--- Prompts for the station's text fields and writes them into the draft.
local function editDetails()
    local input = lib.inputDialog('Station details', {
        { type = 'input', label = 'Id', description = 'Unique, no spaces', required = true, default = draft.id },
        { type = 'input', label = 'Label', required = true, default = draft.label },
        { type = 'number', label = 'Frequency', required = true, default = draft.frequency },
        { type = 'input', label = 'Stream URL', description = 'Direct audio stream or media link, blank for talk-only', default = draft.streamUrl },
        { type = 'input', label = 'Icon', description = 'FontAwesome solid name, e.g. guitar', default = draft.icon },
        { type = 'input', label = 'Description', default = draft.description },
        { type = 'input', label = 'Host jobs', description = 'Comma separated, blank for staff only', default = table.concat(draft.hostJobs, ', ') },
    })

    if not input then return end

    draft.id          = tostring(input[1]):gsub('%s+', '')
    draft.label       = input[2]
    draft.frequency   = math.floor(tonumber(input[3]) or 0)
    draft.streamUrl   = input[4] or ''
    draft.icon        = input[5] ~= '' and input[5] or 'radio'
    draft.description = input[6] or ''
    draft.hostJobs    = splitList(input[7])
end

--- Zone list with add, re-place and delete actions.
local function showZonesMenu()
    -- Refresh the parent so its counts are current when the user backs out
    registerStationMenu()

    local options = {
        {
            title       = 'Add zone',
            description = 'Place a new broadcast box in the world',
            icon        = 'plus',
            onSelect    = function()
                local zone = placeBox(nil)
                if zone then draft.zones[#draft.zones + 1] = zone end
                showZonesMenu()
            end,
        },
    }

    for index, zone in ipairs(draft.zones) do
        options[#options + 1] = {
            title        = ('Zone %d'):format(index),
            description  = ('%.1f, %.1f, %.1f  •  %.1f x %.1f x %.1f  •  %.0f deg')
                :format(zone.coords.x, zone.coords.y, zone.coords.z, zone.size.x, zone.size.y, zone.size.z, zone.heading),
            icon         = 'vector-square',
            metadata     = { { label = 'Tip', value = 'Select to re-place, use the arrow to delete' } },
            arrow        = true,
            onSelect     = function()
                local replaced = placeBox(zone)
                if replaced then draft.zones[index] = replaced end
                showZonesMenu()
            end,
            onArrowClick = function()
                table.remove(draft.zones, index)
                showZonesMenu()
            end,
        }
    end

    lib.registerContext({ id = MENU_ZONES, title = 'Broadcast zones', menu = MENU_STATION, options = options })
    lib.showContext(MENU_ZONES)
end

--- Target list with add, re-place and delete actions.
local function showTargetsMenu()
    registerStationMenu()

    local options = {
        {
            title       = 'Add target point',
            description = 'Aim at a spot and confirm to place it',
            icon        = 'plus',
            onSelect    = function()
                local coords = pickCoords()
                if coords then
                    local input = lib.inputDialog('Target point', {
                        { type = 'input', label = 'Label', default = draft.label ~= '' and draft.label or 'Radio Station' },
                        { type = 'input', label = 'Icon', default = 'fa-solid fa-tower-broadcast' },
                        { type = 'number', label = 'Radius', default = 1.0, min = 0.1, max = 10.0 },
                    })
                    if input then
                        draft.targets[#draft.targets + 1] = {
                            coords = { x = coords.x, y = coords.y, z = coords.z },
                            label  = input[1],
                            icon   = input[2],
                            radius = tonumber(input[3]) or 1.0,
                        }
                    end
                end
                showTargetsMenu()
            end,
        },
    }

    for index, target in ipairs(draft.targets) do
        options[#options + 1] = {
            title        = target.label,
            description  = ('%.1f, %.1f, %.1f  •  radius %.1f')
                :format(target.coords.x, target.coords.y, target.coords.z, target.radius),
            icon         = 'location-dot',
            metadata     = { { label = 'Tip', value = 'Select to re-place, use the arrow to delete' } },
            arrow        = true,
            onSelect     = function()
                local coords = pickCoords()
                if coords then
                    target.coords = { x = coords.x, y = coords.y, z = coords.z }
                end
                showTargetsMenu()
            end,
            onArrowClick = function()
                table.remove(draft.targets, index)
                showTargetsMenu()
            end,
        }
    end

    lib.registerContext({ id = MENU_TARGETS, title = 'Target points', menu = MENU_STATION, options = options })
    lib.showContext(MENU_TARGETS)
end

--- Checks the draft carries the fields the server requires.
---@return string|nil error
local function validateDraft()
    if draft.id == '' then return 'Set an id first' end
    if draft.label == '' then return 'Set a label first' end
    if draft.frequency <= 0 then return 'Set a frequency first' end
    return nil
end

--- Rebuilds the editing menu for the current draft without displaying it.
registerStationMenu = function()
    local options = {
        {
            title       = 'Details',
            description = ('%s  •  %d MHz'):format(draft.label ~= '' and draft.label or 'unnamed', draft.frequency),
            icon        = 'pen',
            onSelect    = function()
                editDetails()
                showStationMenu()
            end,
        },
        {
            title       = 'Broadcast zones',
            description = ('%d configured'):format(#draft.zones),
            icon        = 'vector-square',
            arrow       = true,
            onSelect    = showZonesMenu,
        },
        {
            title       = 'Target points',
            description = ('%d configured'):format(#draft.targets),
            icon        = 'location-dot',
            arrow       = true,
            onSelect    = showTargetsMenu,
        },
        {
            title       = 'Save station',
            description = 'Send to the server and apply for everyone',
            icon        = 'floppy-disk',
            onSelect    = function()
                local err = validateDraft()
                if err then
                    Notify(err, 'error')
                    showStationMenu()
                    return
                end
                TriggerServerEvent('cad-radiostation:editor:save', draft, draftOriginalId)
                draft, draftOriginalId = nil, nil
            end,
        },
    }

    if draftOriginalId then
        options[#options + 1] = {
            title       = 'Delete station',
            description = 'Remove it for everyone',
            icon        = 'trash',
            iconColor   = '#ef4444',
            onSelect    = function()
                local confirm = lib.alertDialog({
                    header   = 'Delete station',
                    content  = ('Delete "%s" permanently?'):format(draft.label),
                    centered = true,
                    cancel   = true,
                    labels   = { confirm = 'Delete', cancel = 'Keep' },
                })
                if confirm == 'confirm' then
                    TriggerServerEvent('cad-radiostation:editor:delete', draftOriginalId)
                    draft, draftOriginalId = nil, nil
                else
                    showStationMenu()
                end
            end,
        }
    end

    lib.registerContext({
        id      = MENU_STATION,
        title   = draftOriginalId and ('Edit: ' .. draft.label) or 'New station',
        menu    = MENU_MAIN,
        options = options,
    })
end

--- Rebuilds and displays the editing menu.
showStationMenu = function()
    registerStationMenu()
    lib.showContext(MENU_STATION)
end

--- Loads a station's full record into the draft and opens the editing menu.
---@param stationId string
local function editStation(stationId)
    local station = lib.callback.await('cad-radiostation:getStationForEdit', false, stationId)
    if not station then
        Notify('Could not load that station', 'error')
        return
    end

    draft = station
    draftOriginalId = stationId
    showStationMenu()
end

--- Station list, plus the create and reset actions.
showMainMenu = function()
    local options = {
        {
            title       = 'Create station',
            description = 'Start a new station from scratch',
            icon        = 'plus',
            onSelect    = function()
                draft = newDraft()
                draftOriginalId = nil
                editDetails()
                showStationMenu()
            end,
        },
    }

    for _, station in ipairs(Stations.GetAll()) do
        options[#options + 1] = {
            title       = station.label,
            description = ('%d MHz  •  %d zone(s), %d target(s)')
                :format(station.frequency, #station.zones, #station.targets),
            icon        = 'radio',
            onSelect    = function() editStation(station.id) end,
        }
    end

    options[#options + 1] = {
        title       = 'Reset to config defaults',
        description = 'Discard every in-game change',
        icon        = 'rotate-left',
        iconColor   = '#f59e0b',
        onSelect    = function()
            local confirm = lib.alertDialog({
                header   = 'Reset stations',
                content  = 'Replace the current station list with the server config defaults?',
                centered = true,
                cancel   = true,
                labels   = { confirm = 'Reset', cancel = 'Cancel' },
            })
            if confirm == 'confirm' then
                TriggerServerEvent('cad-radiostation:editor:reset')
            else
                showMainMenu()
            end
        end,
    }

    lib.registerContext({ id = MENU_MAIN, title = 'Radio stations', options = options })
    lib.showContext(MENU_MAIN)
end

RegisterCommand(ClientConfig.editorCommand, function()
    if not lib.callback.await('cad-radiostation:canEdit', false) then
        Notify('You are not allowed to edit stations', 'error')
        return
    end
    showMainMenu()
end, false)
