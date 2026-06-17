-- Police CAD/MDT System - Client Script
-- client.lua

local isNUIOpen = false
local isOnDuty = false
local currentCallsign = nil
local currentDepartment = nil
local officerData = nil
local lastLocationUpdate = 0
local lastEmergencyCall = 0
local framework = nil
local activeGunfireZones = {} -- Track active zones to prevent spam: { {x, y, radius, blip, pointBlip, expiresAt} }
local spawnedNPCs = {}

-- NPC interaction state (declared early so OpenNUI can reference npcInteracting)
local npcLocationMap = {}   -- Map entity handle -> loc for qb-target event lookup
local nearNPC = false
local npcInteracting = false
local npcInteractStart = 0

-- ============================================================
-- NPC Target System (ox_target / qb-target)
-- Declared early so NPC spawning and initialization can reference these
-- ============================================================
local targetSystem = nil -- 'ox_target' | 'qb-target' | nil

local function DetectTargetSystem()
    local configured = Config.NPCs and Config.NPCs.TargetSystem or 'auto'

    if configured == 'ox_target' then
        targetSystem = 'ox_target'
    elseif configured == 'qb-target' then
        targetSystem = 'qb-target'
    elseif configured == 'none' then
        targetSystem = nil
    else
        -- Auto-detect
        if GetResourceState('ox_target') == 'started' then
            targetSystem = 'ox_target'
        elseif GetResourceState('qb-target') == 'started' then
            targetSystem = 'qb-target'
        end
    end

    if Config.Logging.Enabled then
        print('[CAD] Target system: ' .. (targetSystem or 'none (fallback to keypress)'))
    end
end

-- Add target options to a spawned NPC ped
local function AddNPCTargetOptions(pedHandle, npcType, loc)
    if not targetSystem then return end

    if targetSystem == 'ox_target' then
        if npcType == 'dmv' then
            exports.ox_target:addLocalEntity(pedHandle, {
                {
                    name = 'cad_dmv_register',
                    icon = 'fas fa-car',
                    label = 'Register Vehicle',
                    onSelect = function()
                        OpenDMVRegistration(loc)
                    end,
                    distance = 2.5,
                },
            })
        elseif npcType == 'civreg' then
            exports.ox_target:addLocalEntity(pedHandle, {
                {
                    name = 'cad_civ_register',
                    icon = 'fas fa-id-card',
                    label = 'Register Civilian ID',
                    onSelect = function()
                        OpenCivilianRegistration(loc)
                    end,
                    distance = 2.5,
                },
            })
        elseif npcType == 'gunlicense' then
            exports.ox_target:addLocalEntity(pedHandle, {
                {
                    name = 'cad_gun_license',
                    icon = 'fas fa-shield-halved',
                    label = 'Apply for Gun License',
                    onSelect = function()
                        OpenGunLicense(loc)
                    end,
                    distance = 2.5,
                },
            })
        elseif npcType == 'insurance' then
            exports.ox_target:addLocalEntity(pedHandle, {
                {
                    name = 'cad_insurance',
                    icon = 'fas fa-car-burst',
                    label = 'Get Vehicle Insurance',
                    onSelect = function()
                        OpenInsurance(loc)
                    end,
                    distance = 2.5,
                },
            })
        end
    elseif targetSystem == 'qb-target' then
        if npcType == 'dmv' then
            exports['qb-target']:AddTargetEntity(pedHandle, {
                options = {
                    {
                        type = 'client',
                        event = 'cad-mdt:client:openDMV',
                        icon = 'fas fa-car',
                        label = 'Register Vehicle',
                        loc = loc,
                    },
                },
                distance = 2.5,
            })
        elseif npcType == 'civreg' then
            exports['qb-target']:AddTargetEntity(pedHandle, {
                options = {
                    {
                        type = 'client',
                        event = 'cad-mdt:client:openCivReg',
                        icon = 'fas fa-id-card',
                        label = 'Register Civilian ID',
                        loc = loc,
                    },
                },
                distance = 2.5,
            })
        elseif npcType == 'gunlicense' then
            exports['qb-target']:AddTargetEntity(pedHandle, {
                options = {
                    {
                        type = 'client',
                        event = 'cad-mdt:client:openGunLicense',
                        icon = 'fas fa-shield-halved',
                        label = 'Apply for Gun License',
                        loc = loc,
                    },
                },
                distance = 2.5,
            })
        elseif npcType == 'insurance' then
            exports['qb-target']:AddTargetEntity(pedHandle, {
                options = {
                    {
                        type = 'client',
                        event = 'cad-mdt:client:openInsurance',
                        icon = 'fas fa-car-burst',
                        label = 'Get Vehicle Insurance',
                        loc = loc,
                    },
                },
                distance = 2.5,
            })
        end
    end
end

-- Tablet prop/animation state
local tabletObj = nil
local tabletAnimDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local tabletAnimName = "base"
local tabletProp = `prop_cs_tablet`

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

    if Config.Logging.Enabled then
        print('[CAD] Detected framework: ' .. framework)
    end
end

-- ============================================================
-- Framework Getters
-- ============================================================
local function GetPlayerData()
    if framework == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        return QBCore.Functions.GetPlayerData()
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        return ESX.GetPlayerData()
    elseif framework == 'qbox' then
        return exports.qbx_core:GetPlayerData()
    end
    return nil
end

local function GetPlayerIdentifier()
    if framework == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local pd = QBCore.Functions.GetPlayerData()
        return pd and pd.citizenid or nil
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local pd = ESX.GetPlayerData()
        return pd and pd.identifier or nil
    elseif framework == 'qbox' then
        local pd = exports.qbx_core:GetPlayerData()
        return pd and pd.citizenid or nil
    end
    return GetPlayerServerId(PlayerId())
end

local function GetCharacterName()
    if framework == 'qbcore' then
        local pd = GetPlayerData()
        if pd and pd.charinfo then
            return pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
        end
    elseif framework == 'esx' then
        local pd = GetPlayerData()
        if pd then
            return (pd.firstName or 'Unknown') .. ' ' .. (pd.lastName or 'Unknown')
        end
    elseif framework == 'qbox' then
        local pd = GetPlayerData()
        if pd and pd.charinfo then
            return pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
        end
    end
    return 'Unknown'
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

local function GetPlayerJob()
    if framework == 'qbcore' then
        local pd = GetPlayerData()
        return pd and pd.job and pd.job.name or 'unemployed'
    elseif framework == 'esx' then
        local pd = GetPlayerData()
        return pd and pd.job and pd.job.name or 'unemployed'
    elseif framework == 'qbox' then
        local pd = GetPlayerData()
        return pd and pd.job and pd.job.name or 'unemployed'
    end
    return 'unemployed'
end

-- ============================================================
-- HTTP Helper (server callbacks)
-- Uses a callback registry to avoid duplicate event handlers
-- ============================================================
local apiCallbacks = {}

RegisterNetEvent('cad:api:response')
AddEventHandler('cad:api:response', function(urlPath, response)
    if apiCallbacks[urlPath] then
        local cb = apiCallbacks[urlPath]
        apiCallbacks[urlPath] = nil
        if response then
            cb(response.success, response.data)
        else
            cb(false, nil)
        end
    end
end)

local function APIRequest(endpoint, method, data, cb)
    if cb then
        apiCallbacks[method] = cb
    end
    TriggerServerEvent('cad:api:request', endpoint, method, data)
end

-- ============================================================
-- NUI Management
-- ============================================================
-- ============================================================
-- Tablet Prop & Animation
-- ============================================================
local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then return false end
    end
    return true
end

local function LoadModel(model)
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) do
        Citizen.Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then return false end
    end
    return true
end

local function AttachTablet()
    local ped = PlayerPedId()

    -- Load animation dict
    if not LoadAnimDict(tabletAnimDict) then return end

    -- Play tablet animation
    TaskPlayAnim(ped, tabletAnimDict, tabletAnimName, 3.0, 3.0, -1, 49, 0, false, false, false)

    -- Load and attach tablet prop
    if not LoadModel(tabletProp) then return end

    local coords = GetEntityCoords(ped)
    tabletObj = CreateObject(tabletProp, coords.x, coords.y, coords.z, true, true, true)
    AttachEntityToEntity(tabletObj, ped, GetPedBoneIndex(ped, 57005), -- Right hand
        0.12, 0.06, -0.04,   -- Position offset
        10.0, 0.0, 10.0,     -- Rotation offset
        true, true, false, true, 1, true
    )
end

local function RemoveTablet()
    local ped = PlayerPedId()

    -- Stop animation
    StopAnimTask(ped, tabletAnimDict, tabletAnimName, 1.0)

    -- Delete tablet prop
    if tabletObj and DoesEntityExist(tabletObj) then
        DetachEntity(tabletObj, true, true)
        DeleteEntity(tabletObj)
        tabletObj = nil
    end
end

local function OpenNUI()
    if isNUIOpen then return end

    -- Don't open MDT while NPC interaction is active
    if npcInteracting then return end

    -- Check if allowed
    if not Config.NUI.AllowOnFoot and not IsPedInAnyVehicle(PlayerPedId()) then
        return
    end

    isNUIOpen = true
    SetNuiFocus(true, true)

    -- Attach tablet prop and play animation
    AttachTablet()

    SendNUIMessage({
        action = 'open',
        officerData = officerData,
        isOnDuty = isOnDuty,
    })
end

local function CloseNUI()
    if not isNUIOpen then return end

    isNUIOpen = false
    SetNuiFocus(false, false)

    -- Remove tablet prop and stop animation
    RemoveTablet()

    SendNUIMessage({
        action = 'close',
    })
end

RegisterNUICallback('close', function(_, cb)
    CloseNUI()
    cb('ok')
end)

-- ============================================================
-- Duty System
-- ============================================================
local function GoOnDuty(callsign, departmentCode)
    if isOnDuty then return end

    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:duty:on', identifier, callsign, departmentCode)

    isOnDuty = true
    currentCallsign = callsign
    currentDepartment = departmentCode

    -- Notify player
    TriggerEvent('QBCore:Notify', 'You are now on duty as ' .. callsign, 'success')
end

local function GoOffDuty()
    if not isOnDuty then return end

    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:duty:off', identifier)

    isOnDuty = false
    currentCallsign = nil
    currentDepartment = nil
    officerData = nil

    TriggerEvent('QBCore:Notify', 'You are now off duty', 'primary')
end

RegisterNetEvent('cad:duty:statusChanged')
AddEventHandler('cad:duty:statusChanged', function(data)
    isOnDuty = data.onDuty
    officerData = data.officer

    SendNUIMessage({
        action = 'dutyChanged',
        isOnDuty = isOnDuty,
        officerData = officerData,
    })

    -- Show notification
    if isOnDuty then
        TriggerEvent('cad:notify', 'You are now ON DUTY. You will receive dispatch and gunfire notifications.', 'success')
    else
        TriggerEvent('cad:notify', 'You are now OFF DUTY.', 'primary')
    end
end)

-- ============================================================
-- Gunfire Alert (received by on-duty officers from server)
-- ============================================================
RegisterNetEvent('cad:gunfire:alert')
AddEventHandler('cad:gunfire:alert', function(data)
    if not isOnDuty then return end
    if not Config.Gunfire or not Config.Gunfire.Enabled then return end

    local streetName = data.streetName or 'Unknown Location'

    -- Show notification to officer
    TriggerEvent('cad:notify', '🔫 SHOTS FIRED at ' .. streetName, 'error')

    -- Play alert sound
    if Config.Notifications and Config.Notifications.Sound then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end

    -- Create blip at gunfire location
    if Config.Gunfire.BlipDuration > 0 and data.lat and data.lng then
        local radius = Config.Gunfire.DetectionRadius * 0.5
        local blip = AddBlipForRadius(data.lat, data.lng, 0.0, radius)
        SetBlipColour(blip, Config.Gunfire.BlipColor)
        SetBlipAlpha(blip, 80)
        SetBlipAsShortRange(blip, false)

        local pointBlip = AddBlipForCoord(data.lat, data.lng, 0.0)
        SetBlipSprite(pointBlip, Config.Gunfire.BlipSprite)
        SetBlipColour(pointBlip, Config.Gunfire.BlipColor)
        SetBlipScale(pointBlip, Config.Gunfire.BlipScale)
        SetBlipAsShortRange(pointBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Shots Fired - ' .. streetName)
        EndTextCommandSetBlipName(pointBlip)

        -- Track in active zones to prevent duplicates
        local currentTime = GetGameTimer()
        table.insert(activeGunfireZones, {
            x = data.lat,
            y = data.lng,
            radius = radius,
            blip = blip,
            pointBlip = pointBlip,
            expiresAt = currentTime + (Config.Gunfire.BlipDuration * 1000),
        })

        -- Remove blips after duration
        Citizen.SetTimeout(Config.Gunfire.BlipDuration * 1000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            if DoesBlipExist(pointBlip) then RemoveBlip(pointBlip) end
        end)
    end
end)

-- ============================================================
-- Location Updates
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.Location.UpdateInterval)

        if isOnDuty or not Config.Location.OnlyWhileOnDuty then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            if GetGameTimer() - lastLocationUpdate >= Config.Location.UpdateInterval then
                TriggerServerEvent('cad:location:update', coords.x, coords.y)
                lastLocationUpdate = GetGameTimer()
            end
        end
    end
end)

-- ============================================================
-- 911 Command
-- ============================================================
if Config.Emergency.Enabled then
    RegisterCommand(Config.Emergency.Command, function(source, args)
        local currentTime = GetGameTimer()
        if currentTime - lastEmergencyCall < (Config.Emergency.Cooldown * 1000) then
            TriggerEvent('QBCore:Notify', 'Please wait before calling 911 again.', 'error')
            return
        end

        local description = table.concat(args, ' ')
        if #description < 3 then
            TriggerEvent('QBCore:Notify', 'Please provide a description. Usage: /911 [description]', 'error')
            return
        end

        if #description > Config.Emergency.MaxDescriptionLength then
            description = string.sub(description, 1, Config.Emergency.MaxDescriptionLength)
        end

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
        local charName = GetCharacterName()

        TriggerServerEvent('cad:emergency:call', {
            callerName = charName,
            description = description,
            location = streetName,
            lat = coords.x,
            lng = coords.y,
            type = 'Emergency',
        })

        lastEmergencyCall = currentTime
        TriggerEvent('QBCore:Notify', '911 call submitted. Help is on the way.', 'success')
    end, false)
end

-- ============================================================
-- Plate Check Command
-- ============================================================
if Config.PlateCheck.Enabled then
    RegisterCommand(Config.PlateCheck.Command, function(source, args)
        if not isOnDuty then
            TriggerEvent('QBCore:Notify', 'You must be on duty to run plates.', 'error')
            return
        end

        local plate = args[1]

        -- If no plate argument, try to get plate from nearby vehicle
        if not plate or plate == '' then
            local ped = PlayerPedId()

            -- First try: vehicle player is in
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                    plate = GetVehicleNumberPlateText(veh)
                end
            end

            -- Second try: closest vehicle in front / nearby
            if not plate or plate == '' then
                local coords = GetEntityCoords(ped)
                local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 71)
                if veh and veh ~= 0 then
                    plate = GetVehicleNumberPlateText(veh)
                end
            end
        end

        if not plate or plate == '' or #plate < 1 then
            TriggerEvent('QBCore:Notify', 'Usage: /plate [number] or stand near a vehicle', 'error')
            return
        end

        TriggerServerEvent('cad:plate:check', plate)
        TriggerEvent('QBCore:Notify', 'Running plate: ' .. plate, 'primary')
    end, false)
end

RegisterNetEvent('cad:plate:result')
AddEventHandler('cad:plate:result', function(result)
    -- Send to NUI if open, otherwise show notification
    if isNUIOpen then
        SendNUIMessage({
            action = 'plateResult',
            data = result,
        })
    else
        -- Show detailed notification with owner name
        if result.found then
            local msg = result.plate .. ' — ' .. result.color .. ' ' .. result.model
            if result.year then
                msg = msg .. ' (' .. result.year .. ')'
            end
            if result.owner then
                msg = msg .. ' | Owner: ' .. result.owner
            end
            if result.registration then
                msg = msg .. ' | Reg: ' .. result.registration
            end
            if result.stolen then
                msg = msg .. ' | ⚠️ STOLEN'
            end
            if result.flags and #result.flags > 0 then
                msg = msg .. ' | FLAGS: ' .. table.concat(result.flags, ', ')
            end
            local notifyType = (result.stolen or (result.flags and #result.flags > 0)) and 'error' or 'success'
            TriggerEvent('QBCore:Notify', msg, notifyType, 10000)
        else
            TriggerEvent('QBCore:Notify', result.message or 'Vehicle not found', 'primary', 5000)
        end
    end
end)

-- ============================================================
-- Dispatch Notifications
-- ============================================================
RegisterNetEvent('cad:dispatch:newCall')
AddEventHandler('cad:dispatch:newCall', function(call)
    if not Config.Notifications.DispatchNotifications then return end
    if not isOnDuty then return end

    SendNUIMessage({
        action = 'newDispatchCall',
        data = call,
    })

    -- Play notification sound
    if Config.Notifications.Sound then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
end)

RegisterNetEvent('cad:dispatch:callUpdate')
AddEventHandler('cad:dispatch:callUpdate', function(call)
    SendNUIMessage({
        action = 'updateDispatchCall',
        data = call,
    })
end)

RegisterNetEvent('cad:bolo:alert')
AddEventHandler('cad:bolo:alert', function(bolo)
    if not Config.Notifications.BOLOAlerts then return end
    if not isOnDuty then return end

    SendNUIMessage({
        action = 'boloAlert',
        data = bolo,
    })

    if Config.Notifications.Sound then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
end)

RegisterNetEvent('cad:notification')
AddEventHandler('cad:notification', function(notification)
    SendNUIMessage({
        action = 'notification',
        data = notification,
    })
end)

-- ============================================================
-- NUI Callbacks
-- ============================================================

RegisterNUICallback('goOnDuty', function(data, cb)
    GoOnDuty(data.callsign, data.department)
    cb('ok')
end)

RegisterNUICallback('goOffDuty', function(_, cb)
    GoOffDuty()
    cb('ok')
end)

RegisterNUICallback('updateStatus', function(data, cb)
    TriggerServerEvent('cad:status:update', data.status, data.detail)
    cb('ok')
end)

RegisterNUICallback('getGameData', function(_, cb)
    cb({
        isOnDuty = isOnDuty,
        callsign = currentCallsign,
        department = currentDepartment,
        officerData = officerData,
        playerName = GetCharacterName(),
        job = GetPlayerJob(),
    })
end)

-- ============================================================
-- Exports
-- ============================================================

function GetOfficerStatus()
    if not isOnDuty then return 'OFF_DUTY' end
    return officerData and officerData.status or 'AVAILABLE'
end

function IsOfficerOnDuty()
    return isOnDuty
end

function GetOfficerCallsign()
    return currentCallsign
end

-- ============================================================
-- ID Card System
-- ============================================================
local isIDCardOpen = false

local function ShowIDCard()
    if isIDCardOpen then return end
    isIDCardOpen = true

    -- Fetch character info from server/API
    TriggerServerEvent('cad:character:info')
end

local function HideIDCard()
    if not isIDCardOpen then return end
    isIDCardOpen = false
    SendNUIMessage({ action = 'hideIDCard' })
end

RegisterNetEvent('cad:character:infoResult')
AddEventHandler('cad:character:infoResult', function(result)
    if not isIDCardOpen then return end

    if result and result.found and result.character then
        local char = result.character
        SendNUIMessage({
            action = 'showIDCard',
            character = char,
        })
    else
        TriggerEvent('cad:notify', 'No active character found. Register at City Hall first.', 'error')
        isIDCardOpen = false
    end
end)

if Config.IDCard and Config.IDCard.Enabled then
    RegisterCommand('idcard_toggle', function()
        if isIDCardOpen then
            HideIDCard()
        else
            ShowIDCard()
        end
    end, false)

    RegisterKeyMapping('idcard_toggle', 'Show ID Card', 'keyboard', Config.IDCard.Keybind)
end

-- ============================================================
-- Keybind
-- ============================================================
RegisterCommand('cad_toggle', function()
    if isNUIOpen then
        CloseNUI()
    else
        OpenNUI()
    end
end, false)

RegisterKeyMapping('cad_toggle', 'Open CAD/MDT', 'keyboard', Config.NUI.Keybind)

-- ============================================================
-- Initialization
-- ============================================================
Citizen.CreateThread(function()
    DetectFramework()
    DetectTargetSystem()

    if Config.Logging.Enabled then
        print('[CAD] Client initialized. Press ' .. string.upper(Config.NUI.Keybind) .. ' to open MDT.')
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CloseNUI()
        -- Cleanup spawned NPCs
        for _, npcPed in pairs(spawnedNPCs) do
            if DoesEntityExist(npcPed) then
                DeleteEntity(npcPed)
            end
        end
        spawnedNPCs = {}
    end
end)

-- ============================================================
-- /duty Command
-- ============================================================
if Config.DutyCommand and Config.DutyCommand.Enabled then
    RegisterCommand(Config.DutyCommand.Command, function(source, args)
        local identifier = GetPlayerIdentifier()
        if not identifier then
            TriggerEvent('cad:notify', 'Unable to identify you.', 'error')
            return
        end

        if isOnDuty then
            -- Toggle off duty
            TriggerServerEvent('cad:duty:toggle', identifier)
        else
            -- Toggle on duty - need callsign and department
            local callsign = args[1]
            local departmentCode = args[2]

            if Config.DutyCommand.RequireCallsign and (not callsign or callsign == '') then
                TriggerEvent('cad:notify', 'Usage: /duty [callsign] [department] — e.g. /duty 1-ADAM-12 LSPD', 'error')
                return
            end

            if not departmentCode or departmentCode == '' then
                -- Try to get department from player job
                local job = GetPlayerJob()
                departmentCode = string.upper(job)
                -- Map common job names to department codes
                local jobMap = {
                    police = 'LSPD', lspd = 'LSPD', bcso = 'BCSO',
                    sahp = 'SAHP', sheriff = 'BCSO', trooper = 'SAHP',
                }
                departmentCode = jobMap[string.lower(job)] or 'LSPD'
            end

            TriggerServerEvent('cad:duty:toggle', identifier, callsign, departmentCode)
        end
    end, false)

    -- Auto-complete suggestions
    TriggerEvent('chat:addSuggestion', '/' .. Config.DutyCommand.Command, 'Toggle duty status', {
        { name = 'callsign', help = 'Your callsign (e.g. 1-ADAM-12)' },
        { name = 'department', help = 'Department code (LSPD, BCSO, SAHP)' },
    })
end

-- ============================================================
-- Gunfire Detection System
-- ============================================================
-- Check if a gunshot location is inside an existing active zone
local function IsInsideActiveZone(x, y)
    local now = GetGameTimer()
    for i = #activeGunfireZones, 1, -1 do
        local zone = activeGunfireZones[i]
        if now > zone.expiresAt then
            if DoesBlipExist(zone.blip) then RemoveBlip(zone.blip) end
            if DoesBlipExist(zone.pointBlip) then RemoveBlip(zone.pointBlip) end
            table.remove(activeGunfireZones, i)
        else
            local dx = x - zone.x
            local dy = y - zone.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < zone.radius then
                return true
            end
        end
    end
    return false
end

if Config.Gunfire and Config.Gunfire.Enabled then
    local lastGunfireReport = 0

    local function IsWeaponIgnored(weaponHash)
        for _, w in ipairs(Config.Gunfire.IgnoredWeapons or {}) do
            if GetHashKey(w) == weaponHash then
                return true
            end
        end
        return false
    end

    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(100)
            local ped = PlayerPedId()

            if IsPedShooting(ped) then
                local currentWeapon = GetSelectedPedWeapon(ped)

                if not IsWeaponIgnored(currentWeapon) then
                    local currentTime = GetGameTimer()
                    if currentTime - lastGunfireReport > (Config.Gunfire.Cooldown * 1000) then
                        local coords = GetEntityCoords(ped)

                        -- Only report if this is OUTSIDE all existing active zones
                        if not IsInsideActiveZone(coords.x, coords.y) then
                            lastGunfireReport = currentTime
                            local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))

                            -- Report to server for dispatch call + police notification
                            TriggerServerEvent('cad:gunfire:report', {
                                lat = coords.x,
                                lng = coords.y,
                                streetName = streetName,
                                weapon = currentWeapon,
                            })

                            -- Create local blips for on-duty officers
                            if Config.Gunfire.BlipDuration > 0 and isOnDuty then
                                local radius = Config.Gunfire.DetectionRadius * 0.5
                                local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
                                SetBlipColour(blip, Config.Gunfire.BlipColor)
                                SetBlipAlpha(blip, 80)
                                SetBlipAsShortRange(blip, false)

                                local pointBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
                                SetBlipSprite(pointBlip, Config.Gunfire.BlipSprite)
                                SetBlipColour(pointBlip, Config.Gunfire.BlipColor)
                                SetBlipScale(pointBlip, Config.Gunfire.BlipScale)
                                SetBlipAsShortRange(pointBlip, false)
                                BeginTextCommandSetBlipName('STRING')
                                AddTextComponentSubstringPlayerName('Shots Fired - ' .. streetName)
                                EndTextCommandSetBlipName(pointBlip)

                                -- Track this zone so we don't create duplicates
                                local expiresAt = currentTime + (Config.Gunfire.BlipDuration * 1000)
                                table.insert(activeGunfireZones, {
                                    x = coords.x,
                                    y = coords.y,
                                    radius = radius,
                                    blip = blip,
                                    pointBlip = pointBlip,
                                    expiresAt = expiresAt,
                                })

                                -- Remove blips after duration
                                Citizen.SetTimeout(Config.Gunfire.BlipDuration * 1000, function()
                                    if DoesBlipExist(blip) then RemoveBlip(blip) end
                                    if DoesBlipExist(pointBlip) then RemoveBlip(pointBlip) end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- NPC Blips & Spawning
-- ============================================================
Citizen.CreateThread(function()
    -- DMV Blips
    if Config.NPCs and Config.NPCs.DMV and Config.NPCs.DMV.Enabled then
        for _, loc in ipairs(Config.NPCs.DMV.Locations) do
            if loc.blip then
                local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
                SetBlipSprite(blip, loc.blip.sprite)
                SetBlipColour(blip, loc.blip.color)
                SetBlipScale(blip, loc.blip.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(loc.blip.label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    -- Civilian Registration Blips
    if Config.NPCs and Config.NPCs.CivilianReg and Config.NPCs.CivilianReg.Enabled then
        for _, loc in ipairs(Config.NPCs.CivilianReg.Locations) do
            if loc.blip then
                local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
                SetBlipSprite(blip, loc.blip.sprite)
                SetBlipColour(blip, loc.blip.color)
                SetBlipScale(blip, loc.blip.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(loc.blip.label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    -- Gun License Blips
    if Config.NPCs and Config.NPCs.GunLicense and Config.NPCs.GunLicense.Enabled then
        for _, loc in ipairs(Config.NPCs.GunLicense.Locations) do
            if loc.blip then
                local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
                SetBlipSprite(blip, loc.blip.sprite)
                SetBlipColour(blip, loc.blip.color)
                SetBlipScale(blip, loc.blip.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(loc.blip.label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    -- Insurance Agent Blips
    if Config.NPCs and Config.NPCs.Insurance and Config.NPCs.Insurance.Enabled then
        for _, loc in ipairs(Config.NPCs.Insurance.Locations) do
            if loc.blip then
                local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
                SetBlipSprite(blip, loc.blip.sprite)
                SetBlipColour(blip, loc.blip.color)
                SetBlipScale(blip, loc.blip.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(loc.blip.label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end)

-- Spawn NPC peds

Citizen.CreateThread(function()
    if not Config.NPCs then return end

    -- Wait for game to load
    Citizen.Wait(3000)

    -- Spawn DMV NPCs
    if Config.NPCs.DMV and Config.NPCs.DMV.Enabled then
        for i, loc in ipairs(Config.NPCs.DMV.Locations) do
            local model = GetHashKey(loc.model or 's_m_m_linecook')
            RequestModel(model)
            while not HasModelLoaded(model) do Citizen.Wait(10) end

            local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.heading, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedDiesWhenInjured(ped, false)
            SetPedCanPlayAmbientAnims(ped, true)
            SetPedCanRagdollFromPlayerImpact(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)

            spawnedNPCs['dmv_' .. i] = ped
            SetModelAsNoLongerNeeded(model)

            -- Store loc for qb-target event lookup and add target options
            npcLocationMap[ped] = loc
            AddNPCTargetOptions(ped, 'dmv', loc)
        end
    end

    -- Spawn Civilian Registration NPCs
    if Config.NPCs.CivilianReg and Config.NPCs.CivilianReg.Enabled then
        for i, loc in ipairs(Config.NPCs.CivilianReg.Locations) do
            local model = GetHashKey(loc.model or 's_f_y_scrubs_01')
            RequestModel(model)
            while not HasModelLoaded(model) do Citizen.Wait(10) end

            local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.heading, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedDiesWhenInjured(ped, false)
            SetPedCanPlayAmbientAnims(ped, true)
            SetPedCanRagdollFromPlayerImpact(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)

            spawnedNPCs['civreg_' .. i] = ped
            SetModelAsNoLongerNeeded(model)

            -- Store loc for qb-target event lookup and add target options
            npcLocationMap[ped] = loc
            AddNPCTargetOptions(ped, 'civreg', loc)
        end
    end

    -- Spawn Gun License NPCs
    if Config.NPCs.GunLicense and Config.NPCs.GunLicense.Enabled then
        for i, loc in ipairs(Config.NPCs.GunLicense.Locations) do
            local model = GetHashKey(loc.model or 's_m_m_ammucountry')
            RequestModel(model)
            while not HasModelLoaded(model) do Citizen.Wait(10) end

            local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.heading, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedDiesWhenInjured(ped, false)
            SetPedCanPlayAmbientAnims(ped, true)
            SetPedCanRagdollFromPlayerImpact(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)

            spawnedNPCs['gunlicense_' .. i] = ped
            SetModelAsNoLongerNeeded(model)

            npcLocationMap[ped] = loc
            AddNPCTargetOptions(ped, 'gunlicense', loc)
        end
    end

    -- Spawn Insurance Agent NPCs
    if Config.NPCs.Insurance and Config.NPCs.Insurance.Enabled then
        for i, loc in ipairs(Config.NPCs.Insurance.Locations) do
            local model = GetHashKey(loc.model or 'a_m_y_business_03')
            RequestModel(model)
            while not HasModelLoaded(model) do Citizen.Wait(10) end

            local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.heading, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedDiesWhenInjured(ped, false)
            SetPedCanPlayAmbientAnims(ped, true)
            SetPedCanRagdollFromPlayerImpact(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)

            spawnedNPCs['insurance_' .. i] = ped
            SetModelAsNoLongerNeeded(model)

            npcLocationMap[ped] = loc
            AddNPCTargetOptions(ped, 'insurance', loc)
        end
    end
end)

-- qb-target uses events (can't pass closures), so we look up loc by entity
RegisterNetEvent('cad-mdt:client:openDMV')
AddEventHandler('cad-mdt:client:openDMV', function(data)
    local entity = data and data.entity
    local loc = entity and npcLocationMap[entity]
    if loc then
        OpenDMVRegistration(loc)
    end
end)

RegisterNetEvent('cad-mdt:client:openCivReg')
AddEventHandler('cad-mdt:client:openCivReg', function(data)
    local entity = data and data.entity
    local loc = entity and npcLocationMap[entity]
    if loc then
        OpenCivilianRegistration(loc)
    end
end)

RegisterNetEvent('cad-mdt:client:openGunLicense')
AddEventHandler('cad-mdt:client:openGunLicense', function(data)
    local entity = data and data.entity
    local loc = entity and npcLocationMap[entity]
    if loc then
        OpenGunLicense(loc)
    end
end)

RegisterNetEvent('cad-mdt:client:openInsurance')
AddEventHandler('cad-mdt:client:openInsurance', function(data)
    local entity = data and data.entity
    local loc = entity and npcLocationMap[entity]
    if loc then
        OpenInsurance(loc)
    end
end)

-- Fallback: NPC Interaction Thread (key E) when no target system is available
if not targetSystem then
    Citizen.CreateThread(function()
        if not Config.NPCs then return end
        -- Wait for target detection to happen first
        Citizen.Wait(2000)
        if targetSystem then return end -- A target system was detected, skip keypress fallback

        while true do
            Citizen.Wait(0)
            -- Last resort: release focus after 120s to prevent permanent lock if NUI callback never fires
            if npcInteracting and (GetGameTimer() - npcInteractStart > 120000) then
                npcInteracting = false
                SetNuiFocus(false, false)
            end
            if npcInteracting then goto continue end

            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            nearNPC = false

            -- Check DMV NPCs
            if Config.NPCs.DMV and Config.NPCs.DMV.Enabled then
                for _, loc in ipairs(Config.NPCs.DMV.Locations) do
                    local dist = #(coords - loc.coords)
                    if dist < (Config.NPCs.DMV.InteractionDistance or 2.5) then
                        nearNPC = true
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to register a vehicle at ' .. loc.name)
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustPressed(0, 38) then
                            npcInteracting = true
                            npcInteractStart = GetGameTimer()
                            OpenDMVRegistration(loc)
                        end
                        break
                    end
                end
            end

            -- Check Civilian Registration NPCs
            if not nearNPC and Config.NPCs.CivilianReg and Config.NPCs.CivilianReg.Enabled then
                for _, loc in ipairs(Config.NPCs.CivilianReg.Locations) do
                    local dist = #(coords - loc.coords)
                    if dist < (Config.NPCs.CivilianReg.InteractionDistance or 2.5) then
                        nearNPC = true
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to register for a civilian ID at ' .. loc.name)
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustPressed(0, 38) then
                            npcInteracting = true
                            npcInteractStart = GetGameTimer()
                            OpenCivilianRegistration(loc)
                        end
                        break
                    end
                end
            end

            -- Check Gun License NPCs
            if not nearNPC and Config.NPCs.GunLicense and Config.NPCs.GunLicense.Enabled then
                for _, loc in ipairs(Config.NPCs.GunLicense.Locations) do
                    local dist = #(coords - loc.coords)
                    if dist < (Config.NPCs.GunLicense.InteractionDistance or 2.5) then
                        nearNPC = true
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to apply for a gun license at ' .. loc.name)
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustPressed(0, 38) then
                            npcInteracting = true
                            npcInteractStart = GetGameTimer()
                            OpenGunLicense(loc)
                        end
                        break
                    end
                end
            end

            -- Check Insurance Agent NPCs
            if not nearNPC and Config.NPCs.Insurance and Config.NPCs.Insurance.Enabled then
                for _, loc in ipairs(Config.NPCs.Insurance.Locations) do
                    local dist = #(coords - loc.coords)
                    if dist < (Config.NPCs.Insurance.InteractionDistance or 2.5) then
                        nearNPC = true
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to get vehicle insurance at ' .. loc.name)
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustPressed(0, 38) then
                            npcInteracting = true
                            npcInteractStart = GetGameTimer()
                            OpenInsurance(loc)
                        end
                        break
                    end
                end
            end

            if not nearNPC then
                Citizen.Wait(500)
            end

            ::continue::
        end
    end)
end

-- DMV Vehicle Registration UI (Multi-Character)
function OpenDMVRegistration(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()

    -- Grab focus IMMEDIATELY so the game doesn't capture keypresses
    SetNuiFocus(true, true)

    -- Get the vehicle the player is currently in
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = ''
    local model = ''
    local color = ''
    local year = ''

    if vehicle and vehicle ~= 0 then
        plate = GetVehicleNumberPlateText(vehicle) or ''
        local vehModel = GetEntityModel(vehicle)
        model = GetDisplayNameFromVehicleModel(vehModel)
        local c1, c2 = GetVehicleColours(vehicle)
        -- Convert color index to name
        local colorNames = {[0]='Black',[1]='Black',[2]='Black',[3]='Silver',[4]='Silver',[5]='Blue',[6]='Silver',[7]='Silver',[8]='Silver',[9]='Brown',[10]='Silver',[11]='Silver',
            [12]='Red',[13]='Red',[14]='Gold',[15]='Green',[16]='Green',[17]='Blue',[18]='Blue',[19]='Blue',[20]='Silver',[21]='Silver',[22]='Blue',[23]='Blue',
            [24]='Red',[25]='Red',[26]='Red',[27]='Red',[28]='Gold',[29]='Gold',[30]='Silver',[31]='Blue',[32]='Blue',[33]='Silver',[34]='Silver',[35]='Silver',
            [36]='Silver',[37]='Gold',[38]='Orange',[39]='Orange',[40]='Orange',[41]='Orange',[42]='Yellow',[43]='Yellow',[44]='Silver',[45]='Silver',[46]='Silver',
            [47]='Green',[48]='Green',[49]='Green',[50]='Gold',[51]='Gold',[52]='Blue',[53]='Blue',[54]='Silver',[55]='Silver',[56]='Silver',[57]='Silver',
            [58]='Gold',[59]='Gold',[60]='Gold',[61]='Silver',[62]='Blue',[63]='Blue',[64]='Red',[65]='Red',[66]='Red',[67]='Silver',[68]='Blue',[69]='Blue',
            [70]='Green',[71]='Green',[72]='Silver',[73]='Silver',[74]='Yellow',[75]='Yellow',[76]='Yellow',[77]='Gold',[78]='Gold',[79]='Silver',[80]='Silver',
            [81]='Silver',[82]='Blue',[83]='Blue',[84]='Blue',[85]='Purple',[86]='Purple',[87]='Red',[88]='Gold',[89]='Gold',[90]='Gold',[91]='Silver',
            [92]='Silver',[93]='Silver',[94]='Silver',[95]='Silver',[96]='Silver',[97]='Silver',[98]='Gold',[99]='Gold',[100]='Red',[101]='Red',[102]='Silver',
            [103]='Silver',[104]='Silver',[105]='Green',[106]='Green',[107]='Green',[108]='Green',[109]='Green',[110]='Blue',[111]='Blue',[112]='Silver',[113]='Gold',
            [114]='Gold',[115]='Gold',[116]='Gold',[117]='Silver',[118]='Silver',[119]='Silver',[120]='Silver',[121]='Silver',[122]='Silver',[123]='Red',[124]='Red',
            [125]='Red',[126]='Red',[127]='Silver',[128]='Silver',[129]='Silver',[130]='Silver',[131]='Silver',[132]='Black',[133]='Silver',[134]='Gold',[135]='Gold',
            [136]='Purple',[137]='Purple',[138]='Orange',[139]='Orange',[140]='Green',[141]='Green',[142]='Red',[143]='Red',[144]='Black',[145]='Gold',[146]='Gold',
            [147]='Silver',[148]='Silver',[149]='Purple',[150]='Purple',[151]='Silver',[152]='Silver',[153]='Silver',[154]='Silver',[155]='Silver',[156]='Silver',}
        color = colorNames[c1] or 'Unknown'
        year = tostring(GetVehicleModelYear(vehModel))
    end

    -- Fetch characters for the DMV owner selector
    local identifier = GetPlayerIdentifier()
    APIRequest('POST', '/characters', { identifier = identifier }, function(success, result)
        local characters = {}
        if success and result and result.success then
            characters = result.characters or {}
        end

        -- Focus already grabbed above; just send the form data
        SendNUIMessage({
            action = 'openDMVRegistration',
            location = loc.name,
            plate = plate,
            model = model,
            color = color,
            year = year,
            cost = Config.NPCs.DMV.RegistrationCost or 0,
            characters = characters,
        })
    end)
end

-- Civilian Registration UI (Multi-Character)
function OpenCivilianRegistration(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()

    -- Grab focus IMMEDIATELY so the game doesn't capture keypresses
    SetNuiFocus(true, true)

    local charName = GetCharacterName()
    local firstName, lastName = '', ''
    if charName and charName ~= 'Unknown' then
        local space = string.find(charName, ' ')
        if space then
            firstName = string.sub(charName, 1, space - 1)
            lastName = string.sub(charName, space + 1)
        else
            firstName = charName
        end
    end

    -- Fetch the player's existing characters first
    local identifier = GetPlayerIdentifier()
    APIRequest('POST', '/characters', { identifier = identifier }, function(success, result)
        local characters = {}
        if success and result and result.success then
            characters = result.characters or {}
        end

        -- Focus already grabbed above; just send the form data
        SendNUIMessage({
            action = 'openCivilianRegistration',
            location = loc.name,
            firstName = firstName,
            lastName = lastName,
            characters = characters,
            identifier = identifier,
        })
    end)
end

-- Gun License Application UI (mirrors OpenCivilianRegistration pattern)
function OpenGunLicense(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()

    -- Grab focus IMMEDIATELY so the game doesn't capture keypresses
    SetNuiFocus(true, true)

    -- Fetch the player's existing characters first
    local identifier = GetPlayerIdentifier()
    APIRequest('POST', '/characters', { identifier = identifier }, function(success, result)
        local characters = {}
        if success and result and result.success then
            characters = result.characters or {}
        end

        -- Focus already grabbed above; just send the form data
        SendNUIMessage({
            action = 'openGunLicense',
            location = loc.name,
            characters = characters,
            identifier = identifier,
        })
    end)
end

-- Insurance Agent UI (mirrors OpenCivilianRegistration pattern)
function OpenInsurance(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()

    -- Grab focus IMMEDIATELY so the game doesn't capture keypresses
    SetNuiFocus(true, true)

    -- Fetch the player's existing characters and their vehicles
    local identifier = GetPlayerIdentifier()
    APIRequest('POST', '/characters', { identifier = identifier }, function(success, result)
        local characters = {}
        if success and result and result.success then
            characters = result.characters or {}
        end

        -- Get vehicles for the active character
        local vehicles = {}
        for _, c in ipairs(characters) do
            if c.isActive and c.vehicles then
                vehicles = c.vehicles
                break
            end
        end

        -- Focus already grabbed above; just send the form data
        SendNUIMessage({
            action = 'openInsurance',
            location = loc.name,
            characters = characters,
            vehicles = vehicles,
            identifier = identifier,
        })
    end)
end

-- NUI Callbacks for NPC interactions
RegisterNUICallback('submitVehicleRegistration', function(data, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:dmv:register', {
        identifier = identifier,
        plate = data.plate,
        model = data.model,
        color = data.color,
        year = data.year,
        civilianId = data.civilianId, -- optional: specific character to register under
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitCivilianRegistration', function(data, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:civilian:register', {
        identifier = identifier,
        firstName = data.firstName,
        lastName = data.lastName,
        dateOfBirth = data.dateOfBirth,
        gender = data.gender,
        address = data.address,
        phone = data.phone,
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:character:select', {
        identifier = identifier,
        civilianId = data.civilianId,
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('fetchCharacters', function(data, cb)
    local identifier = GetPlayerIdentifier()
    APIRequest('POST', '/characters', { identifier = identifier }, function(success, result)
        if success and result and result.success then
            cb(result.characters)
        else
            cb({})
        end
    end)
end)

RegisterNUICallback('cancelNPCInteraction', function(_, cb)
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitGunLicense', function(data, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:gunlicense:apply', {
        identifier = identifier,
        civilianId = data.civilianId,
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitInsurance', function(data, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:insurance:apply', {
        identifier = identifier,
        plate = data.plate,
        civilianId = data.civilianId,
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

-- Generic notification event (for server-triggered notifications)
RegisterNetEvent('cad:notify')
AddEventHandler('cad:notify', function(msg, type)
    TriggerEvent('QBCore:Notify', msg, type or 'primary')
end)
