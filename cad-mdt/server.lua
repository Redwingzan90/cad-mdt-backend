-- Police CAD/MDT System - Server Script
-- server.lua

local framework = nil
local playerDutyCache = {} -- Cache duty status per player

-- ============================================================
-- Framework Detection
-- ============================================================
local function DetectFramework()
    if Config.Framework ~= 'auto' then
        framework = Config.Framework
        return
    end

    if GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        framework = 'esx'
    elseif GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    else
        framework = 'standalone'
    end

    print('[CAD] Server detected framework: ' .. framework)
end

-- ============================================================
-- HTTP Helper
-- ============================================================
local function APIRequest(method, endpoint, data, cb)
    local url = Config.API.URL .. '/api/fivem' .. endpoint

    PerformHttpRequest(url, function(statusCode, responseText, headers)
        local success = statusCode >= 200 and statusCode < 300
        local result = nil

        if responseText and #responseText > 0 then
            local ok, decoded = pcall(json.decode, responseText)
            if ok then
                result = decoded
            end
        end

        if Config.Logging.Enabled and not success then
            print('[CAD] API Error: ' .. method .. ' ' .. endpoint .. ' - Status: ' .. tostring(statusCode))
            if responseText then
                print('[CAD] Response: ' .. string.sub(responseText, 1, 500))
            end
        end

        if cb then
            cb(success, result, statusCode)
        end
    end, method, data and json.encode(data) or '', {
        ['Content-Type'] = 'application/json',
        ['X-Server-Key'] = Config.API.ServerKey,
    })
end

-- ============================================================
-- Framework Getters
-- ============================================================
local function GetPlayerIdentifier(source)
    if framework == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local player = QBCore.Functions.GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local player = ESX.GetPlayerFromId(source)
        return player and player.identifier or nil
    elseif framework == 'qbox' then
        local player = exports.qbx_core:GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    end
    return tostring(source)
end

local function IsPlayerPolice(source)
    if framework == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            local job = player.PlayerData.job and player.PlayerData.job.name or 'unemployed'
            return IsPoliceJob(job)
        end
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local player = ESX.GetPlayerFromId(source)
        if player then
            local job = player.job and player.job.name or 'unemployed'
            return IsPoliceJob(job)
        end
    elseif framework == 'qbox' then
        local player = exports.qbx_core:GetPlayer(source)
        if player then
            local job = player.PlayerData.job and player.PlayerData.job.name or 'unemployed'
            return IsPoliceJob(job)
        end
    end
    return false
end

local function IsPoliceJob(jobName)
    local policeJobs = {
        'police', 'lspd', 'bcso', 'sahp', 'sheriff',
        'trooper', 'officer', 'sergeant', 'lieutenant',
        'captain', 'chief', 'commander',
    }
    for _, j in ipairs(policeJobs) do
        if string.lower(jobName) == j then
            return true
        end
    end
    return false
end

-- ============================================================
-- Duty Events
-- ============================================================
RegisterNetEvent('cad:duty:on')
AddEventHandler('cad:duty:on', function(identifier, callsign, departmentCode)
    local source = source

    APIRequest('POST', '/player-duty', {
        identifier = identifier,
        onDuty = true,
        callsign = callsign,
        departmentCode = departmentCode,
    }, function(success, result)
        if success and result and result.success then
            playerDutyCache[source] = {
                onDuty = true,
                callsign = callsign,
                department = departmentCode,
                identifier = identifier,
            }

            TriggerClientEvent('cad:duty:statusChanged', source, {
                onDuty = true,
                officer = result.officer or {},
            })

            if Config.Logging.Enabled then
                print('[CAD] Player ' .. source .. ' went on duty as ' .. callsign)
            end
        else
            TriggerClientEvent('QBCore:Notify', source, 'Failed to go on duty. Are you registered as an officer?', 'error')
        end
    end)
end)

RegisterNetEvent('cad:duty:off')
AddEventHandler('cad:duty:off', function(identifier)
    local source = source

    APIRequest('POST', '/player-duty', {
        identifier = identifier,
        onDuty = false,
    }, function(success, result)
        playerDutyCache[source] = nil

        TriggerClientEvent('cad:duty:statusChanged', source, {
            onDuty = false,
            officer = nil,
        })

        if Config.Logging.Enabled then
            print('[CAD] Player ' .. source .. ' went off duty')
        end
    end)
end)

-- ============================================================
-- Location Updates
-- ============================================================
RegisterNetEvent('cad:location:update')
AddEventHandler('cad:location:update', function(lat, lng)
    local source = source
    local cache = playerDutyCache[source]

    if not cache or not cache.onDuty then return end

    -- Debounce: only update every few seconds
    local now = os.time()
    if cache.lastLocUpdate and (now - cache.lastLocUpdate) < 3 then return end
    cache.lastLocUpdate = now

    APIRequest('POST', '/location', {
        officerId = cache.officerId,
        lat = lat,
        lng = lng,
    })
end)

-- ============================================================
-- Status Updates
-- ============================================================
RegisterNetEvent('cad:status:update')
AddEventHandler('cad:status:update', function(status, detail)
    local source = source
    local cache = playerDutyCache[source]

    if not cache or not cache.onDuty then return end

    -- Update via API
    APIRequest('POST', '/status', {
        officerId = cache.officerId,
        status = status,
        detail = detail,
    })
end)

-- ============================================================
-- Emergency (911) Calls
-- ============================================================
RegisterNetEvent('cad:emergency:call')
AddEventHandler('cad:emergency:call', function(data)
    local source = source

    APIRequest('POST', '/911', {
        callerName = data.callerName or 'Unknown',
        callerPhone = data.callerPhone,
        description = data.description,
        location = data.location or 'Unknown',
        lat = data.lat,
        lng = data.lng,
        type = data.type or 'Emergency',
    }, function(success, result)
        if success then
            TriggerClientEvent('QBCore:Notify', source, 'Your 911 call has been received.', 'success')
        else
            TriggerClientEvent('QBCore:Notify', source, 'Failed to submit 911 call.', 'error')
        end
    end)
end)

-- ============================================================
-- Plate Check
-- ============================================================
RegisterNetEvent('cad:plate:check')
AddEventHandler('cad:plate:check', function(plate)
    local source = source

    if not IsPlayerPolice(source) and not playerDutyCache[source] then
        TriggerClientEvent('QBCore:Notify', source, 'Access denied.', 'error')
        return
    end

    APIRequest('POST', '/plate-check', {
        plate = plate,
    }, function(success, result)
        if success and result then
            TriggerClientEvent('cad:plate:result', source, result)
        else
            TriggerClientEvent('cad:plate:result', source, {
                found = false,
                plate = plate,
                message = 'Error checking plate.',
            })
        end
    end)
end)

-- ============================================================
-- API Response Handler
-- ============================================================
RegisterNetEvent('cad:api:request')
AddEventHandler('cad:api:request', function(httpMethod, urlPath, data)
    local source = source

    APIRequest(httpMethod or 'GET', urlPath, data, function(success, result)
        TriggerClientEvent('cad:api:response', source, urlPath, {
            success = success,
            data = result,
        })
    end)
end)

-- ============================================================
-- Player Disconnect Cleanup
-- ============================================================
AddEventHandler('playerDropped', function(reason)
    local source = source
    local cache = playerDutyCache[source]

    if cache and cache.onDuty and Config.Duty.AutoGoOffDutyOnDisconnect then
        APIRequest('POST', '/player-duty', {
            identifier = cache.identifier,
            onDuty = false,
        })
    end

    playerDutyCache[source] = nil
end)

-- ============================================================
-- Exports
-- ============================================================

function GetOfficerInfo(source)
    return playerDutyCache[source] or nil
end

function GetActiveCalls(cb)
    APIRequest('GET', '/active-calls', nil, function(success, result)
        if cb then cb(success and result or {}) end
    end)
end

function SubmitEmergencyCall(data, cb)
    APIRequest('POST', '/911', data, function(success, result)
        if cb then cb(success, result) end
    end)
end

function RunPlateCheck(plate, cb)
    APIRequest('POST', '/plate-check', { plate = plate }, function(success, result)
        if cb then cb(success, result) end
    end)
end

-- ============================================================
-- Duty Command Handler
-- ============================================================
RegisterNetEvent('cad:duty:toggle')
AddEventHandler('cad:duty:toggle', function(identifier, callsign, departmentCode)
    local source = source
    local cache = playerDutyCache[source]

    if cache and cache.onDuty then
        -- Go off duty
        APIRequest('POST', '/player-duty', {
            identifier = identifier,
            onDuty = false,
        }, function(success, result)
            playerDutyCache[source] = nil
            TriggerClientEvent('cad:duty:statusChanged', source, {
                onDuty = false,
                officer = nil,
            })
            if Config.Logging.Enabled then
                print('[CAD] Player ' .. source .. ' went off duty via /duty command')
            end
        end)
    else
        -- Go on duty
        APIRequest('POST', '/player-duty', {
            identifier = identifier,
            onDuty = true,
            callsign = callsign,
            departmentCode = departmentCode,
        }, function(success, result)
            if success and result and result.success then
                playerDutyCache[source] = {
                    onDuty = true,
                    callsign = callsign,
                    department = departmentCode,
                    identifier = identifier,
                }
                TriggerClientEvent('cad:duty:statusChanged', source, {
                    onDuty = true,
                    officer = result.officer or {},
                })
                if Config.Logging.Enabled then
                    print('[CAD] Player ' .. source .. ' went on duty via /duty command as ' .. callsign)
                end
            else
                TriggerClientEvent('cad:notify', source, 'Failed to go on duty. Are you registered as an officer?', 'error')
            end
        end)
    end
end)

-- ============================================================
-- Gunfire Detection Handler
-- ============================================================
RegisterNetEvent('cad:gunfire:report')
AddEventHandler('cad:gunfire:report', function(data)
    local source = source
    if not Config.Gunfire.Enabled then return end
    if not Config.Gunfire.NotifyDispatch then return end

    local streetName = data.streetName or 'Unknown Location'
    local weaponHash = data.weapon or 'Unknown'

    local weaponName = weaponHash
    if type(weaponHash) == 'number' then
        weaponName = 'Weapon #' .. tostring(weaponHash)
    end

    -- Create a dispatch call via API
    APIRequest('POST', '/gunfire', {
        lat = data.lat,
        lng = data.lng,
        streetName = streetName,
        weapon = weaponName,
        playerId = source,
    }, function(success, result)
        if success then
            if Config.Logging.Enabled then
                print('[CAD] Gunfire detected at ' .. streetName .. ' by player ' .. source)
            end
        end
    end)

    -- Also directly notify all on-duty officers via client events
    -- so they get the blip and notification immediately
    for playerSource, cache in pairs(playerDutyCache) do
        if cache and cache.onDuty then
            TriggerClientEvent('cad:gunfire:alert', playerSource, {
                lat = data.lat,
                lng = data.lng,
                streetName = streetName,
            })
        end
    end
end)

-- ============================================================
-- Vehicle Registration (DMV)
-- ============================================================
RegisterNetEvent('cad:dmv:register')
AddEventHandler('cad:dmv:register', function(data)
    local source = source

    local identifier = data.identifier
    if not identifier then
        TriggerClientEvent('cad:notify', source, 'Unable to verify your identity.', 'error')
        return
    end

    APIRequest('POST', '/dmv/register', {
        identifier = identifier,
        plate = data.plate,
        model = data.model,
        color = data.color,
        year = data.year,
    }, function(success, result)
        if success and result then
            if result.success then
                TriggerClientEvent('cad:notify', source, 'Vehicle registered! Plate: ' .. (result.plate or data.plate), 'success')
            else
                TriggerClientEvent('cad:notify', source, result.message or 'Registration failed.', 'error')
            end
        else
            TriggerClientEvent('cad:notify', source, 'Failed to register vehicle.', 'error')
        end
    end)
end)

-- ============================================================
-- Civilian Registration (Multi-Character)
-- ============================================================
RegisterNetEvent('cad:civilian:register')
AddEventHandler('cad:civilian:register', function(data)
    local source = source

    local identifier = data.identifier
    if not identifier then
        TriggerClientEvent('cad:notify', source, 'Unable to verify your identity.', 'error')
        return
    end

    APIRequest('POST', '/civilian/register', {
        identifier = identifier,
        firstName = data.firstName,
        lastName = data.lastName,
        dateOfBirth = data.dateOfBirth,
        gender = data.gender,
        address = data.address,
        phone = data.phone,
    }, function(success, result)
        if success and result then
            if result.success then
                local msg = 'Civilian ID registered successfully!'
                if result.licenseNumber then
                    msg = msg .. ' License: ' .. result.licenseNumber
                end
                if result.characterNumber then
                    msg = msg .. ' (Character #' .. result.characterNumber .. ')'
                end
                TriggerClientEvent('cad:notify', source, msg, 'success')
                -- Refresh character list for the player
                TriggerClientEvent('cad:character:refresh', source)
            else
                TriggerClientEvent('cad:notify', source, result.message or 'Registration failed.', 'error')
            end
        else
            TriggerClientEvent('cad:notify', source, 'Failed to register civilian ID.', 'error')
        end
    end)
end)

-- ============================================================
-- Character List (Multi-Character)
-- ============================================================
RegisterNetEvent('cad:characters:list')
AddEventHandler('cad:characters:list', function(data)
    local source = source

    local identifier = data.identifier
    if not identifier then
        TriggerClientEvent('cad:notify', source, 'Unable to verify your identity.', 'error')
        return
    end

    APIRequest('POST', '/characters', {
        identifier = identifier,
    }, function(success, result)
        if success and result and result.success then
            TriggerClientEvent('cad:characters:result', source, result.characters)
        else
            TriggerClientEvent('cad:characters:result', source, {})
        end
    end)
end)

-- ============================================================
-- Character Selection (Multi-Character)
-- ============================================================
RegisterNetEvent('cad:character:select')
AddEventHandler('cad:character:select', function(data)
    local source = source

    local identifier = data.identifier
    local civilianId = data.civilianId
    if not identifier or not civilianId then
        TriggerClientEvent('cad:notify', source, 'Invalid character selection.', 'error')
        return
    end

    APIRequest('POST', '/character/select', {
        identifier = identifier,
        civilianId = civilianId,
    }, function(success, result)
        if success and result then
            if result.success then
                TriggerClientEvent('cad:notify', source, result.message or 'Character switched!', 'success')
                TriggerClientEvent('cad:character:selected', source, result.activeCharacter)
            else
                TriggerClientEvent('cad:notify', source, result.message or 'Selection failed.', 'error')
            end
        else
            TriggerClientEvent('cad:notify', source, 'Failed to switch character.', 'error')
        end
    end)
end)

-- ============================================================
-- Gun License Application
-- ============================================================
RegisterNetEvent('cad:gunlicense:apply')
AddEventHandler('cad:gunlicense:apply', function(data)
    local source = source
    local identifier = data.identifier
    if not identifier then
        TriggerClientEvent('cad:notify', source, 'Unable to verify your identity.', 'error')
        return
    end

    APIRequest('POST', '/gun-license', {
        identifier = identifier,
        civilianId = data.civilianId,
    }, function(success, result)
        if success and result then
            if result.success then
                TriggerClientEvent('cad:notify', source, result.message or 'Gun license issued!', 'success')
            else
                TriggerClientEvent('cad:notify', source, result.message or 'Failed to obtain gun license.', 'error')
            end
        else
            TriggerClientEvent('cad:notify', source, 'Failed to apply for gun license.', 'error')
        end
    end)
end)

-- ============================================================
-- Insurance Application
-- ============================================================
RegisterNetEvent('cad:insurance:apply')
AddEventHandler('cad:insurance:apply', function(data)
    local source = source
    local identifier = data.identifier
    if not identifier then
        TriggerClientEvent('cad:notify', source, 'Unable to verify your identity.', 'error')
        return
    end

    APIRequest('POST', '/insurance', {
        identifier = identifier,
        plate = data.plate,
        civilianId = data.civilianId,
    }, function(success, result)
        if success and result then
            if result.success then
                TriggerClientEvent('cad:notify', source, result.message or 'Insurance activated!', 'success')
            else
                TriggerClientEvent('cad:notify', source, result.message or 'Failed to get insurance.', 'error')
            end
        else
            TriggerClientEvent('cad:notify', source, 'Failed to apply for insurance.', 'error')
        end
    end)
end)

-- ============================================================
-- Character Info (ID Card)
-- ============================================================
RegisterNetEvent('cad:character:info')
AddEventHandler('cad:character:info', function()
    local source = source
    local identifier = GetPlayerIdentifier(source)
    if not identifier then
        TriggerClientEvent('cad:character:infoResult', source, { found = false })
        return
    end

    APIRequest('POST', '/character-info', {
        identifier = identifier,
    }, function(success, result)
        if success and result then
            TriggerClientEvent('cad:character:infoResult', source, result)
        else
            TriggerClientEvent('cad:character:infoResult', source, { found = false })
        end
    end)
end)

-- ============================================================
-- Initialization
-- ============================================================
Citizen.CreateThread(function()
    DetectFramework()
    print('[CAD] Server initialized.')
end)
