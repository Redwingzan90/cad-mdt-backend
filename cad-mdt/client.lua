-- ============================================================
-- CAD-MDT Standalone - Client Script
-- ESX Legacy + oxmysql
-- ============================================================

local ESX = nil
local isNUIOpen = false
local isOnDuty = false
local currentCallsign = nil
local currentDepartment = nil
local officerData = nil
local lastLocationUpdate = 0
local lastEmergencyCall = 0
local spawnedNPCs = {}
local activeGunfireZones = {}

-- NPC interaction state
local npcLocationMap = {}
local nearNPC = false
local npcInteracting = false
local npcInteractStart = 0
local targetSystem = nil

-- Tablet prop/animation state
local tabletObj = nil
local tabletAnimDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local tabletAnimName = "base"
local tabletProp = `prop_cs_tablet`

-- ============================================================
-- ESX Init
-- ============================================================
Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Citizen.Wait(100)
    end
end)

-- ============================================================
-- Helpers
-- ============================================================
local function GetPlayerIdentifier()
    if ESX then
        local pd = ESX.GetPlayerData()
        return pd and pd.identifier or nil
    end
    return GetPlayerServerId(PlayerId())
end

local function GetCharacterName()
    if ESX then
        local pd = ESX.GetPlayerData()
        if pd then
            return (pd.firstName or 'Unknown') .. ' ' .. (pd.lastName or 'Unknown')
        end
    end
    return 'Unknown'
end

local function GetPlayerJob()
    if ESX then
        local pd = ESX.GetPlayerData()
        return pd and pd.job and pd.job.name or 'unemployed'
    end
    return 'unemployed'
end

local function IsPoliceJob(jobName)
    for _, j in ipairs(Config.PoliceJobs) do
        if string.lower(jobName) == string.lower(j) then return true end
    end
    return false
end

-- ============================================================
-- Target System Detection
-- ============================================================
local function DetectTargetSystem()
    local configured = Config.NPCs and Config.NPCs.TargetSystem or 'auto'
    if configured == 'ox_target' then
        targetSystem = 'ox_target'
    elseif configured == 'qb-target' then
        targetSystem = 'qb-target'
    elseif configured == 'none' then
        targetSystem = nil
    else
        if GetResourceState('ox_target') == 'started' then
            targetSystem = 'ox_target'
        elseif GetResourceState('qb-target') == 'started' then
            targetSystem = 'qb-target'
        end
    end
end

local function AddNPCTargetOptions(pedHandle, npcType, loc)
    if not targetSystem then return end
    if targetSystem == 'ox_target' then
        local options = {}
        if npcType == 'dmv' then
            options = {{ name = 'cad_dmv', icon = 'fas fa-car', label = 'Register Vehicle', onSelect = function() OpenDMVRegistration(loc) end, distance = 2.5 }}
        elseif npcType == 'civreg' then
            options = {{ name = 'cad_civreg', icon = 'fas fa-id-card', label = 'Register Civilian ID', onSelect = function() OpenCivilianRegistration(loc) end, distance = 2.5 }}
        elseif npcType == 'gunlicense' then
            options = {{ name = 'cad_gunlicense', icon = 'fas fa-shield-halved', label = 'Apply for Gun License', onSelect = function() OpenGunLicense(loc) end, distance = 2.5 }}
        elseif npcType == 'insurance' then
            options = {{ name = 'cad_insurance', icon = 'fas fa-car-burst', label = 'Get Vehicle Insurance', onSelect = function() OpenInsurance(loc) end, distance = 2.5 }}
        end
        exports.ox_target:addLocalEntity(pedHandle, options)
    elseif targetSystem == 'qb-target' then
        local eventMap = {
            dmv = 'cad-mdt:client:openDMV',
            civreg = 'cad-mdt:client:openCivReg',
            gunlicense = 'cad-mdt:client:openGunLicense',
            insurance = 'cad-mdt:client:openInsurance',
        }
        local labelMap = {
            dmv = 'Register Vehicle',
            civreg = 'Register Civilian ID',
            gunlicense = 'Apply for Gun License',
            insurance = 'Get Vehicle Insurance',
        }
        local iconMap = {
            dmv = 'fas fa-car',
            civreg = 'fas fa-id-card',
            gunlicense = 'fas fa-shield-halved',
            insurance = 'fas fa-car-burst',
        }
        exports['qb-target']:AddTargetEntity(pedHandle, {
            options = {{ type = 'client', event = eventMap[npcType], icon = iconMap[npcType], label = labelMap[npcType], loc = loc }},
            distance = 2.5,
        })
    end
end

-- ============================================================
-- Tablet Prop & Animation
-- ============================================================
local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) do Citizen.Wait(10); timeout = timeout + 10
        if timeout > 5000 then return false end
    end
    return true
end

local function LoadModel(model)
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) do Citizen.Wait(10); timeout = timeout + 10
        if timeout > 5000 then return false end
    end
    return true
end

local function AttachTablet()
    local ped = PlayerPedId()
    if not LoadAnimDict(tabletAnimDict) then return end
    TaskPlayAnim(ped, tabletAnimDict, tabletAnimName, 3.0, 3.0, -1, 49, 0, false, false, false)
    if not LoadModel(tabletProp) then return end
    local coords = GetEntityCoords(ped)
    tabletObj = CreateObject(tabletProp, coords.x, coords.y, coords.z, true, true, true)
    AttachEntityToEntity(tabletObj, ped, GetPedBoneIndex(ped, 57005),
        0.12, 0.06, -0.04, 10.0, 0.0, 10.0, true, true, false, true, 1, true)
end

local function RemoveTablet()
    local ped = PlayerPedId()
    StopAnimTask(ped, tabletAnimDict, tabletAnimName, 1.0)
    if tabletObj and DoesEntityExist(tabletObj) then
        DetachEntity(tabletObj, true, true)
        DeleteEntity(tabletObj)
        tabletObj = nil
    end
end

-- ============================================================
-- NUI Management
-- ============================================================
local function OpenNUI()
    if isNUIOpen then return end
    if npcInteracting then return end
    if not Config.NUI.AllowOnFoot and not IsPedInAnyVehicle(PlayerPedId()) then return end

    isNUIOpen = true
    SetNuiFocus(true, true)
    AttachTablet()

    SendNUIMessage({
        action = 'open',
        officerData = officerData,
        isOnDuty = isOnDuty,
        playerName = GetCharacterName(),
        job = GetPlayerJob(),
        callsign = currentCallsign,
        department = currentDepartment,
    })
end

local function CloseNUI()
    if not isNUIOpen then return end
    isNUIOpen = false
    SetNuiFocus(false, false)
    RemoveTablet()
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    CloseNUI()
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
-- Duty System
-- ============================================================
RegisterNetEvent('cad:duty:statusChanged')
AddEventHandler('cad:duty:statusChanged', function(data)
    isOnDuty = data.onDuty
    officerData = data.officer
    SendNUIMessage({ action = 'dutyChanged', isOnDuty = isOnDuty, officerData = officerData })
end)

RegisterNUICallback('goOnDuty', function(data, cb)
    local identifier = GetPlayerIdentifier()
    if not identifier then cb('error'); return end
    TriggerServerEvent('cad:duty:toggle', identifier, data.callsign, data.department)
    cb('ok')
end)

RegisterNUICallback('goOffDuty', function(_, cb)
    local identifier = GetPlayerIdentifier()
    if not identifier then cb('error'); return end
    TriggerServerEvent('cad:duty:toggle', identifier)
    cb('ok')
end)

RegisterNUICallback('updateStatus', function(data, cb)
    TriggerServerEvent('cad:status:update', data.status, data.detail)
    cb('ok')
end)

-- ============================================================
-- 911 Command
-- ============================================================
if Config.Emergency and Config.Emergency.Enabled then
    RegisterCommand(Config.Emergency.Command, function(_, args)
        local currentTime = GetGameTimer()
        if currentTime - lastEmergencyCall < (Config.Emergency.Cooldown * 1000) then
            TriggerEvent('cad:notify', 'Please wait before calling 911 again.', 'error')
            return
        end
        local description = table.concat(args, ' ')
        if #description < 3 then
            TriggerEvent('cad:notify', 'Usage: /' .. Config.Emergency.Command .. ' [description]', 'error')
            return
        end
        if #description > Config.Emergency.MaxDescriptionLength then
            description = string.sub(description, 1, Config.Emergency.MaxDescriptionLength)
        end
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
        TriggerServerEvent('cad:emergency:call', {
            callerName = GetCharacterName(),
            description = description,
            location = streetName,
            lat = coords.x, lng = coords.y,
            type = 'Emergency',
        })
        lastEmergencyCall = currentTime
        TriggerEvent('cad:notify', '911 call submitted. Help is on the way.', 'success')
    end, false)
end

-- ============================================================
-- Plate Check Command
-- ============================================================
if Config.PlateCheck and Config.PlateCheck.Enabled then
    RegisterCommand(Config.PlateCheck.Command, function(_, args)
        if not isOnDuty then
            TriggerEvent('cad:notify', 'You must be on duty to run plates.', 'error')
            return
        end
        local plate = args[1]
        if not plate or plate == '' then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then plate = GetVehicleNumberPlateText(veh) end
            end
            if not plate or plate == '' then
                local coords = GetEntityCoords(ped)
                local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 71)
                if veh and veh ~= 0 then plate = GetVehicleNumberPlateText(veh) end
            end
        end
        if not plate or plate == '' or #plate < 1 then
            TriggerEvent('cad:notify', 'Usage: /' .. Config.PlateCheck.Command .. ' [number] or stand near a vehicle', 'error')
            return
        end
        TriggerServerEvent('cad:plate:check', plate)
    end, false)
end

RegisterNetEvent('cad:plate:result')
AddEventHandler('cad:plate:result', function(result)
    if isNUIOpen then
        SendNUIMessage({ action = 'plateResult', data = result })
    else
        if result.found then
            local msg = result.plate .. ' — ' .. (result.color or '') .. ' ' .. (result.model or '')
            if result.year then msg = msg .. ' (' .. result.year .. ')' end
            if result.owner then msg = msg .. ' | Owner: ' .. result.owner end
            if result.stolen then msg = msg .. ' | ⚠️ STOLEN' end
            if result.flags and #result.flags > 0 then msg = msg .. ' | ' .. table.concat(result.flags, ', ') end
            TriggerEvent('cad:notify', msg, result.stolen and 'error' or 'success')
        else
            TriggerEvent('cad:notify', result.message or 'Vehicle not found', 'primary')
        end
    end
end)

-- ============================================================
-- Dispatch Notifications
-- ============================================================
RegisterNetEvent('cad:dispatch:newCall')
AddEventHandler('cad:dispatch:newCall', function(call)
    if not isOnDuty then return end
    SendNUIMessage({ action = 'newDispatchCall', data = call })
    if Config.Notifications and Config.Notifications.Sound then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
end)

RegisterNetEvent('cad:dispatch:callUpdate')
AddEventHandler('cad:dispatch:callUpdate', function(call)
    SendNUIMessage({ action = 'updateDispatchCall', data = call })
end)

RegisterNetEvent('cad:dispatch:activeList')
AddEventHandler('cad:dispatch:activeList', function(calls)
    SendNUIMessage({ action = 'activeCallsList', data = calls })
end)

RegisterNetEvent('cad:dispatch:unitList')
AddEventHandler('cad:dispatch:unitList', function(units)
    SendNUIMessage({ action = 'unitList', data = units })
end)

RegisterNetEvent('cad:bolo:alert')
AddEventHandler('cad:bolo:alert', function(bolo)
    if not isOnDuty then return end
    SendNUIMessage({ action = 'boloAlert', data = bolo })
    if Config.Notifications and Config.Notifications.Sound then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
end)

RegisterNetEvent('cad:search:results')
AddEventHandler('cad:search:results', function(result)
    SendNUIMessage({ action = 'searchResults', data = result })
end)

-- ============================================================
-- Gunfire Detection
-- ============================================================
local function IsInsideActiveZone(x, y)
    local now = GetGameTimer()
    for i = #activeGunfireZones, 1, -1 do
        local zone = activeGunfireZones[i]
        if now > zone.expiresAt then
            if DoesBlipExist(zone.blip) then RemoveBlip(zone.blip) end
            if DoesBlipExist(zone.pointBlip) then RemoveBlip(zone.pointBlip) end
            table.remove(activeGunfireZones, i)
        else
            local dx, dy = x - zone.x, y - zone.y
            if math.sqrt(dx * dx + dy * dy) < zone.radius then return true end
        end
    end
    return false
end

RegisterNetEvent('cad:gunfire:alert')
AddEventHandler('cad:gunfire:alert', function(data)
    if not isOnDuty or not Config.Gunfire or not Config.Gunfire.Enabled then return end
    local streetName = data.streetName or 'Unknown'
    TriggerEvent('cad:notify', '🔫 SHOTS FIRED at ' .. streetName, 'error')
    if Config.Gunfire.BlipDuration > 0 and data.lat and data.lng then
        local radius = Config.Gunfire.DetectionRadius * 0.5
        local blip = AddBlipForRadius(data.lat, data.lng, 0.0, radius)
        SetBlipColour(blip, Config.Gunfire.BlipColor)
        SetBlipAlpha(blip, 80)
        local pointBlip = AddBlipForCoord(data.lat, data.lng, 0.0)
        SetBlipSprite(pointBlip, Config.Gunfire.BlipSprite)
        SetBlipColour(pointBlip, Config.Gunfire.BlipColor)
        SetBlipScale(pointBlip, Config.Gunfire.BlipScale)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Shots Fired - ' .. streetName)
        EndTextCommandSetBlipName(pointBlip)
        Citizen.SetTimeout(Config.Gunfire.BlipDuration * 1000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            if DoesBlipExist(pointBlip) then RemoveBlip(pointBlip) end
        end)
    end
end)

if Config.Gunfire and Config.Gunfire.Enabled then
    local lastGunfireReport = 0
    local function IsWeaponIgnored(weaponHash)
        for _, w in ipairs(Config.Gunfire.IgnoredWeapons or {}) do
            if GetHashKey(w) == weaponHash then return true end
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
                        if not IsInsideActiveZone(coords.x, coords.y) then
                            lastGunfireReport = currentTime
                            local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
                            TriggerServerEvent('cad:gunfire:report', { lat = coords.x, lng = coords.y, streetName = streetName, weapon = currentWeapon })
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- Location Updates
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.Location.UpdateInterval)
        if isOnDuty or not Config.Location.OnlyWhileOnDuty then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            TriggerServerEvent('cad:location:update', coords.x, coords.y)
        end
    end
end)

-- ============================================================
-- ID Card System
-- ============================================================
local isIDCardOpen = false

local function ShowIDCard()
    if isIDCardOpen then return end
    isIDCardOpen = true
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
        SendNUIMessage({ action = 'showIDCard', character = result.character })
    else
        TriggerEvent('cad:notify', 'No active character found. Register at City Hall first.', 'error')
        isIDCardOpen = false
    end
end)

if Config.IDCard and Config.IDCard.Enabled then
    RegisterCommand('idcard_toggle', function()
        if isIDCardOpen then HideIDCard() else ShowIDCard() end
    end, false)
    RegisterKeyMapping('idcard_toggle', 'Show ID Card', 'keyboard', Config.IDCard.Keybind)
end

-- ============================================================
-- NPC Functions
-- ============================================================
function OpenDMVRegistration(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()
    SetNuiFocus(true, true)

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate, model, color, year = '', '', '', ''
    if vehicle and vehicle ~= 0 then
        plate = GetVehicleNumberPlateText(vehicle) or ''
        local vehModel = GetEntityModel(vehicle)
        model = GetDisplayNameFromVehicleModel(vehModel)
        local c1 = GetVehicleColours(vehicle)
        local colorNames = {[0]='Black',[1]='Black',[3]='Silver',[5]='Blue',[12]='Red',[14]='Gold',[15]='Green',[17]='Blue',[38]='Orange',[42]='Yellow',[47]='Green',[52]='Blue',[85]='Purple'}
        color = colorNames[c1] or 'Unknown'
        year = tostring(GetVehicleModelYear(vehModel))
    end

    SendNUIMessage({
        action = 'openDMVRegistration',
        location = loc.name,
        plate = plate, model = model, color = color, year = year,
        cost = Config.NPCs.DMV.RegistrationCost or 0,
    })
end

function OpenCivilianRegistration(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()
    SetNuiFocus(true, true)

    local charName = GetCharacterName()
    local firstName, lastName = '', ''
    if charName and charName ~= 'Unknown' then
        local space = string.find(charName, ' ')
        if space then firstName = string.sub(charName, 1, space - 1); lastName = string.sub(charName, space + 1)
        else firstName = charName end
    end

    SendNUIMessage({
        action = 'openCivilianRegistration',
        location = loc.name,
        firstName = firstName, lastName = lastName,
        identifier = GetPlayerIdentifier(),
    })
end

function OpenGunLicense(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openGunLicense',
        location = loc.name,
        identifier = GetPlayerIdentifier(),
    })
end

function OpenInsurance(loc)
    npcInteracting = true
    npcInteractStart = GetGameTimer()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openInsurance',
        location = loc.name,
        identifier = GetPlayerIdentifier(),
    })
end

-- NUI Callbacks for NPC interactions
RegisterNUICallback('submitVehicleRegistration', function(data, cb)
    TriggerServerEvent('cad:dmv:register', { identifier = GetPlayerIdentifier(), plate = data.plate, model = data.model, color = data.color, year = data.year })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitCivilianRegistration', function(data, cb)
    TriggerServerEvent('cad:civilian:register', {
        identifier = GetPlayerIdentifier(),
        firstName = data.firstName, lastName = data.lastName,
        dateOfBirth = data.dateOfBirth, gender = data.gender,
        address = data.address, phone = data.phone,
    })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    TriggerServerEvent('cad:character:select', { identifier = GetPlayerIdentifier(), civilianId = data.civilianId })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('fetchCharacters', function(_, cb)
    local identifier = GetPlayerIdentifier()
    TriggerServerEvent('cad:characters:list', { identifier = identifier })
    cb('ok')
end)

RegisterNUICallback('cancelNPCInteraction', function(_, cb)
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitGunLicense', function(data, cb)
    TriggerServerEvent('cad:gunlicense:apply', { identifier = GetPlayerIdentifier(), civilianId = data.civilianId })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

RegisterNUICallback('submitInsurance', function(data, cb)
    TriggerServerEvent('cad:insurance:apply', { identifier = GetPlayerIdentifier(), plate = data.plate })
    SetNuiFocus(false, false)
    npcInteracting = false
    cb('ok')
end)

-- Dispatch NUI callbacks
RegisterNUICallback('createDispatchCall', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    TriggerServerEvent('cad:dispatch:create', {
        type = data.type, description = data.description,
        location = data.location or streetName,
        lat = coords.x, lng = coords.y,
        priority = data.priority,
    })
    cb('ok')
end)

RegisterNUICallback('respondToCall', function(data, cb)
    TriggerServerEvent('cad:dispatch:respond', data.callId)
    cb('ok')
end)

RegisterNUICallback('completeCall', function(data, cb)
    TriggerServerEvent('cad:dispatch:complete', data.callId)
    cb('ok')
end)

RegisterNUICallback('createBOLO', function(data, cb)
    TriggerServerEvent('cad:bolo:create', data)
    cb('ok')
end)

RegisterNUICallback('createReport', function(data, cb)
    TriggerServerEvent('cad:report:create', data)
    cb('ok')
end)

RegisterNUICallback('searchCivilians', function(data, cb)
    TriggerServerEvent('cad:search:civilians', data.query)
    cb('ok')
end)

RegisterNUICallback('searchVehicles', function(data, cb)
    TriggerServerEvent('cad:search:vehicles', data.query)
    cb('ok')
end)

RegisterNUICallback('getActiveCalls', function(_, cb)
    TriggerServerEvent('cad:dispatch:getActive')
    cb('ok')
end)

RegisterNUICallback('getUnits', function(_, cb)
    TriggerServerEvent('cad:dispatch:getUnits')
    cb('ok')
end)

-- ============================================================
-- Notification
-- ============================================================
RegisterNetEvent('cad:notify')
AddEventHandler('cad:notify', function(msg, type)
    if IsDuiAvailable() then return end
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName(msg)
    DrawNotification(false, false)
end)

RegisterNetEvent('cad:character:result')
AddEventHandler('cad:character:result', function(rows)
    SendNUIMessage({ action = 'charactersList', data = rows })
end)

-- ============================================================
-- Keybind
-- ============================================================
RegisterCommand('cad_toggle', function()
    if isNUIOpen then CloseNUI() else OpenNUI() end
end, false)
RegisterKeyMapping('cad_toggle', 'Open CAD/MDT', 'keyboard', Config.NUI.Keybind)

-- ============================================================
-- NPC Blips & Spawning
-- ============================================================
Citizen.CreateThread(function()
    -- Create blips for all NPC locations
    local npcConfig = Config.NPCs or {}
    local sections = { DMV = npcConfig.DMV, CivilianReg = npcConfig.CivilianReg, GunLicense = npcConfig.GunLicense, Insurance = npcConfig.Insurance }
    for _, section in pairs(sections) do
        if section and section.Enabled and section.Locations then
            for _, loc in ipairs(section.Locations) do
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
    end

    -- Spawn NPC peds
    Citizen.Wait(3000)
    local sections2 = { { cfg = npcConfig.DMV, key = 'dmv', model = 's_m_m_linecook' },
        { cfg = npcConfig.CivilianReg, key = 'civreg', model = 's_f_y_scrubs_01' },
        { cfg = npcConfig.GunLicense, key = 'gunlicense', model = 's_m_m_ammucountry' },
        { cfg = npcConfig.Insurance, key = 'insurance', model = 'a_m_y_business_03' } }

    for _, sec in ipairs(sections2) do
        if sec.cfg and sec.cfg.Enabled and sec.cfg.Locations then
            for i, loc in ipairs(sec.cfg.Locations) do
                local model = GetHashKey(loc.model or sec.model)
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
                spawnedNPCs[sec.key .. '_' .. i] = ped
                SetModelAsNoLongerNeeded(model)
                npcLocationMap[ped] = loc
                AddNPCTargetOptions(ped, sec.key, loc)
            end
        end
    end
end)

-- qb-target event handlers
RegisterNetEvent('cad-mdt:client:openDMV')
AddEventHandler('cad-mdt:client:openDMV', function(data)
    local loc = data and data.entity and npcLocationMap[data.entity]
    if loc then OpenDMVRegistration(loc) end
end)
RegisterNetEvent('cad-mdt:client:openCivReg')
AddEventHandler('cad-mdt:client:openCivReg', function(data)
    local loc = data and data.entity and npcLocationMap[data.entity]
    if loc then OpenCivilianRegistration(loc) end
end)
RegisterNetEvent('cad-mdt:client:openGunLicense')
AddEventHandler('cad-mdt:client:openGunLicense', function(data)
    local loc = data and data.entity and npcLocationMap[data.entity]
    if loc then OpenGunLicense(loc) end
end)
RegisterNetEvent('cad-mdt:client:openInsurance')
AddEventHandler('cad-mdt:client:openInsurance', function(data)
    local loc = data and data.entity and npcLocationMap[data.entity]
    if loc then OpenInsurance(loc) end
end)

-- Fallback: NPC Interaction Thread (key E)
if not targetSystem then
    Citizen.CreateThread(function()
        Citizen.Wait(2000)
        if targetSystem then return end
        while true do
            Citizen.Wait(0)
            if npcInteracting and (GetGameTimer() - npcInteractStart > 120000) then
                npcInteracting = false
                SetNuiFocus(false, false)
            end
            if npcInteracting then goto continue end
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            nearNPC = false
            local sections = {
                { cfg = Config.NPCs and Config.NPCs.DMV, key = 'dmv', label = 'register a vehicle' },
                { cfg = Config.NPCs and Config.NPCs.CivilianReg, key = 'civreg', label = 'register for a civilian ID' },
                { cfg = Config.NPCs and Config.NPCs.GunLicense, key = 'gunlicense', label = 'apply for a gun license' },
                { cfg = Config.NPCs and Config.NPCs.Insurance, key = 'insurance', label = 'get vehicle insurance' },
            }
            for _, sec in ipairs(sections) do
                if sec.cfg and sec.cfg.Enabled and sec.cfg.Locations then
                    for _, loc in ipairs(sec.cfg.Locations) do
                        if #(coords - loc.coords) < (sec.cfg.InteractionDistance or 2.5) then
                            nearNPC = true
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to ' .. sec.label .. ' at ' .. loc.name)
                            EndTextCommandDisplayHelp(0, false, true, -1)
                            if IsControlJustPressed(0, 38) then
                                npcInteracting = true
                                npcInteractStart = GetGameTimer()
                                if sec.key == 'dmv' then OpenDMVRegistration(loc)
                                elseif sec.key == 'civreg' then OpenCivilianRegistration(loc)
                                elseif sec.key == 'gunlicense' then OpenGunLicense(loc)
                                elseif sec.key == 'insurance' then OpenInsurance(loc)
                                end
                            end
                            break
                        end
                    end
                end
                if nearNPC then break end
            end
            if not nearNPC then Citizen.Wait(500) end
            ::continue::
        end
    end)
end

-- ============================================================
-- Init & Cleanup
-- ============================================================
Citizen.CreateThread(function()
    DetectTargetSystem()
    if Config.Logging.Enabled then
        print('[CAD] Client initialized. Press ' .. string.upper(Config.NUI.Keybind) .. ' to open MDT.')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CloseNUI()
        for _, npcPed in pairs(spawnedNPCs) do
            if DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
        end
        spawnedNPCs = {}
    end
end)
