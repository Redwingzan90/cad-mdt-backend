-- ============================================================
-- CAD-MDT Standalone - Server Script
-- ESX Legacy + oxmysql
-- ============================================================

local ESX = nil
local PlayerDutyCache = {} -- source -> { onDuty, callsign, department, identifier, officerId }

-- ============================================================
-- ESX Init
-- ============================================================
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- ============================================================
-- Helpers
-- ============================================================
local function Tbl(name)
    return Config.TablePrefix .. name
end

local function GenNumber(prefix)
    return prefix .. '-' .. tostring(os.time()):sub(-6) .. math.random(10,99)
end

local function IsPoliceJob(jobName)
    for _, j in ipairs(Config.PoliceJobs) do
        if string.lower(jobName) == string.lower(j) then return true end
    end
    return false
end

local function NotifyClient(source, msg, type)
    TriggerClientEvent('cad:notify', source, msg, type or 'primary')
end

-- ============================================================
-- Officer Registration / On-Duty
-- ============================================================
RegisterNetEvent('cad:officer:register')
AddEventHandler('cad:officer:register', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local identifier = xPlayer.identifier
    local firstname = data.firstname or 'Unknown'
    local lastname = data.lastname or 'Unknown'
    local badgeNumber = data.badgeNumber or '0000'
    local department = data.department or 'LSPD'
    local rank = data.rank or 'Officer'

    MySQL.insert(('INSERT INTO %s (identifier, firstname, lastname, badge_number, department, rank) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE firstname=?, lastname=?, badge_number=?, department=?, rank=?'):format(Tbl('officers')),
        { identifier, firstname, lastname, badgeNumber, department, rank, firstname, lastname, badgeNumber, department, rank },
        function(id)
            TriggerClientEvent('cad:officer:registered', src, { id = id, identifier = identifier })
        end
    )
end)

RegisterNetEvent('cad:officer:setCallsign')
AddEventHandler('cad:officer:setCallsign', function(callsign)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    MySQL.update(('UPDATE %s SET callsign = ? WHERE identifier = ?'):format(Tbl('officers')), { callsign, xPlayer.identifier })
end)

-- ============================================================
-- Duty Toggle
-- ============================================================
RegisterNetEvent('cad:duty:toggle')
AddEventHandler('cad:duty:toggle', function(identifier, callsign, department)
    local src = source

    MySQL.query(('SELECT * FROM %s WHERE identifier = ?'):format(Tbl('officers')), { identifier }, function(rows)
        if not rows or #rows == 0 then
            NotifyClient(src, 'No officer profile found. Register at City Hall first.', 'error')
            return
        end

        local officer = rows[1]
        local currentlyOnDuty = officer.on_duty == 1

        if currentlyOnDuty then
            -- Go OFF duty
            MySQL.update(('UPDATE %s SET on_duty = 0, status = ?, callsign = NULL WHERE identifier = ?'):format(Tbl('officers')),
                { 'OFF_DUTY', identifier })
            PlayerDutyCache[src] = nil
            TriggerClientEvent('cad:duty:statusChanged', src, { onDuty = false })
            NotifyClient(src, 'You are now OFF DUTY.', 'primary')
        else
            -- Go ON duty
            local newCallsign = callsign or officer.callsign or '1-ALPHA'
            local newDept = department or officer.department

            MySQL.update(('UPDATE %s SET on_duty = 1, status = ?, callsign = ?, department = ? WHERE identifier = ?'):format(Tbl('officers')),
                { 'AVAILABLE', newCallsign, newDept, identifier })

            PlayerDutyCache[src] = {
                onDuty = true,
                callsign = newCallsign,
                department = newDept,
                identifier = identifier,
                officerId = officer.id,
            }

            TriggerClientEvent('cad:duty:statusChanged', src, {
                onDuty = true,
                officer = { id = officer.id, callsign = newCallsign, department = newDept, firstname = officer.firstname, lastname = officer.lastname },
            })
            NotifyClient(src, 'You are now ON DUTY as ' .. newCallsign, 'success')
        end
    end)
end)

-- ============================================================
-- Location Updates
-- ============================================================
RegisterNetEvent('cad:location:update')
AddEventHandler('cad:location:update', function(lat, lng)
    local src = source
    local cache = PlayerDutyCache[src]
    if not cache or not cache.onDuty then return end

    local now = os.time()
    if cache.lastLocUpdate and (now - cache.lastLocUpdate) < 3 then return end
    cache.lastLocUpdate = now

    MySQL.update(('UPDATE %s SET last_lat = ?, last_lng = ?, last_update = NOW() WHERE identifier = ?'):format(Tbl('officers')),
        { lat, lng, cache.identifier })
end)

-- ============================================================
-- Status Updates
-- ============================================================
RegisterNetEvent('cad:status:update')
AddEventHandler('cad:status:update', function(status, detail)
    local src = source
    local cache = PlayerDutyCache[src]
    if not cache or not cache.onDuty then return end

    MySQL.update(('UPDATE %s SET status = ?, status_detail = ? WHERE identifier = ?'):format(Tbl('officers')),
        { status, detail, cache.identifier })

    TriggerClientEvent('cad:status:updated', src, { status = status, detail = detail })
end)

-- ============================================================
-- Dispatch Calls
-- ============================================================
RegisterNetEvent('cad:dispatch:create')
AddEventHandler('cad:dispatch:create', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local callNumber = GenNumber('CAD')
    local callType = data.type or 'UNKNOWN'
    local description = data.description or ''
    local location = data.location or 'Unknown'
    local lat = data.lat
    local lng = data.lng
    local priority = data.priority or 'PRIORITY_3'

    MySQL.insert(('INSERT INTO %s (call_number, type, description, location, lat, lng, priority, creator_identifier) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(Tbl('dispatch_calls')),
        { callNumber, callType, description, location, lat, lng, priority, xPlayer.identifier },
        function(id)
            local call = { id = id, call_number = callNumber, type = callType, description = description, location = location, lat = lat, lng = lng, priority = priority, status = 'PENDING', creator_identifier = xPlayer.identifier }

            -- Notify all on-duty officers
            for plySrc, cache in pairs(PlayerDutyCache) do
                if cache.onDuty then
                    TriggerClientEvent('cad:dispatch:newCall', plySrc, call)
                end
            end

            TriggerClientEvent('cad:dispatch:created', src, call)
        end
    )
end)

RegisterNetEvent('cad:dispatch:respond')
AddEventHandler('cad:dispatch:respond', function(callId)
    local src = source
    local cache = PlayerDutyCache[src]
    if not cache or not cache.onDuty then return end

    MySQL.update(('UPDATE %s SET status = ?, handler_identifier = ? WHERE id = ?'):format(Tbl('dispatch_calls')),
        { 'ASSIGNED', cache.identifier, callId })

    TriggerClientEvent('cad:dispatch:callUpdate', src, { id = callId, status = 'ASSIGNED' })
end)

RegisterNetEvent('cad:dispatch:complete')
AddEventHandler('cad:dispatch:complete', function(callId)
    MySQL.update(('UPDATE %s SET status = ?, completed_at = NOW() WHERE id = ?'):format(Tbl('dispatch_calls')),
        { 'COMPLETED', callId })

    TriggerClientEvent('cad:dispatch:callUpdate', -1, { id = callId, status = 'COMPLETED' })
end)

-- ============================================================
-- 911 Calls
-- ============================================================
RegisterNetEvent('cad:emergency:call')
AddEventHandler('cad:emergency:call', function(data)
    local src = source

    MySQL.insert(('INSERT INTO %s (caller_name, caller_phone, description, location, lat, lng, type, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(Tbl('emergency_calls')),
        { data.callerName or 'Unknown', data.callerPhone, data.description, data.location or 'Unknown', data.lat, data.lng, data.type or 'Emergency', 'PENDING' },
        function(id)
            NotifyClient(src, 'Your 911 call has been received. Help is on the way.', 'success')

            -- Notify on-duty officers
            for plySrc, cache in pairs(PlayerDutyCache) do
                if cache.onDuty then
                    TriggerClientEvent('cad:dispatch:newCall', plySrc, { id = id, type = '911', description = data.description, location = data.location, priority = 'PRIORITY_1' })
                end
            end
        end
    )
end)

-- ============================================================
-- Plate Check
-- ============================================================
RegisterNetEvent('cad:plate:check')
AddEventHandler('cad:plate:check', function(plate)
    local src = source
    local cache = PlayerDutyCache[src]
    if not cache or not cache.onDuty then
        NotifyClient(src, 'You must be on duty to run plates.', 'error')
        return
    end

    MySQL.query(('SELECT v.*, c.firstname, c.lastname, c.date_of_birth FROM %s v LEFT JOIN %s c ON v.owner_id = c.id WHERE v.plate = ?'):format(Tbl('vehicles'), Tbl('civilians')),
        { string.upper(plate) },
        function(rows)
            if not rows or #rows == 0 then
                TriggerClientEvent('cad:plate:result', src, { found = false, plate = plate, message = 'Vehicle not registered.' })
                return
            end

            local v = rows[1]
            local flags = {}
            if v.stolen == 1 then table.insert(flags, 'STOLEN') end
            if v.registration_status ~= 'VALID' then table.insert(flags, 'REG ' .. v.registration_status) end

            -- Check for warrants on owner
            MySQL.query(('SELECT * FROM %s WHERE civilian_id = ? AND status = ?'):format(Tbl('warrants')),
                { v.owner_id, 'ACTIVE' },
                function(warrants)
                    if warrants and #warrants > 0 then
                        table.insert(flags, 'OWNER HAS WARRANTS')
                    end

                    TriggerClientEvent('cad:plate:result', src, {
                        found = true,
                        plate = v.plate,
                        model = v.model,
                        color = v.color,
                        year = v.year,
                        owner = (v.firstname or 'Unknown') .. ' ' .. (v.lastname or ''),
                        ownerDOB = v.date_of_birth,
                        registration = v.registration_status,
                        insurance = v.insurance_status,
                        stolen = v.stolen == 1,
                        flags = flags,
                    })
                end
            )
        end
    )
end)

-- ============================================================
-- Civilian Registration
-- ============================================================
RegisterNetEvent('cad:civilian:register')
AddEventHandler('cad:civilian:register', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local identifier = data.identifier or xPlayer.identifier

    -- Deactivate current active character
    MySQL.update(('UPDATE %s SET is_active = 0 WHERE identifier = ? AND is_active = 1'):format(Tbl('civilians')), { identifier })

    MySQL.insert(('INSERT INTO %s (identifier, firstname, lastname, date_of_birth, gender, address, phone, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, 1)'):format(Tbl('civilians')),
        { identifier, data.firstName, data.lastName, data.dateOfBirth, data.gender, data.address, data.phone },
        function(civId)
            -- Auto-issue driver's license
            local licNum = 'DL' .. tostring(os.time()):sub(-8) .. math.random(10,99)
            MySQL.insert(('INSERT INTO %s (civilian_id, type, number, status, issued_at, expires_at) VALUES (?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR))'):format(Tbl('licenses')),
                { civId, 'drivers', licNum, 'VALID' })

            NotifyClient(src, 'Civilian ID registered! License: ' .. licNum, 'success')
        end
    )
end)

-- ============================================================
-- Characters List
-- ============================================================
RegisterNetEvent('cad:characters:list')
AddEventHandler('cad:characters:list', function(data)
    local src = source
    local identifier = data.identifier

    MySQL.query(('SELECT c.*, GROUP_CONCAT(DISTINCT l.type SEPARATOR \",\") as license_types FROM %s c LEFT JOIN %s l ON c.id = l.civilian_id WHERE c.identifier = ? AND c.active = 1 GROUP BY c.id'):format(Tbl('civilians'), Tbl('licenses')),
        { identifier },
        function(rows)
            TriggerClientEvent('cad:characters:result', src, rows or {})
        end
    )
end)

-- ============================================================
-- Character Selection
-- ============================================================
RegisterNetEvent('cad:character:select')
AddEventHandler('cad:character:select', function(data)
    local src = source
    local identifier = data.identifier
    local civilianId = data.civilianId

    MySQL.update(('UPDATE %s SET is_active = 0 WHERE identifier = ?'):format(Tbl('civilians')), { identifier })
    MySQL.update(('UPDATE %s SET is_active = 1 WHERE id = ? AND identifier = ?'):format(Tbl('civilians')), { civilianId, identifier })

    NotifyClient(src, 'Character switched!', 'success')
end)

-- ============================================================
-- DMV Vehicle Registration
-- ============================================================
RegisterNetEvent('cad:dmv:register')
AddEventHandler('cad:dmv:register', function(data)
    local src = source
    local identifier = data.identifier

    -- Find active civilian
    MySQL.query(('SELECT * FROM %s WHERE identifier = ? AND is_active = 1 AND active = 1 LIMIT 1'):format(Tbl('civilians')),
        { identifier },
        function(rows)
            if not rows or #rows == 0 then
                NotifyClient(src, 'Register as a civilian first at City Hall.', 'error')
                return
            end

            local civ = rows[1]
            local plate = string.upper(string.sub(data.plate or '', 1, 8))

            -- Check duplicate
            MySQL.query(('SELECT id FROM %s WHERE plate = ?'):format(Tbl('vehicles')), { plate }, function(existing)
                if existing and #existing > 0 then
                    NotifyClient(src, 'This plate is already registered.', 'error')
                    return
                end

                MySQL.insert(('INSERT INTO %s (plate, model, color, year, owner_id, registration_status, insurance_status) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(Tbl('vehicles')),
                    { plate, data.model or 'Unknown', data.color or 'Unknown', data.year, civ.id, 'VALID', 'NONE' },
                    function()
                        NotifyClient(src, 'Vehicle registered! Plate: ' .. plate, 'success')
                    end
                )
            end)
        end
    )
end)

-- ============================================================
-- Gun License
-- ============================================================
RegisterNetEvent('cad:gunlicense:apply')
AddEventHandler('cad:gunlicense:apply', function(data)
    local src = source
    local identifier = data.identifier

    MySQL.query(('SELECT * FROM %s WHERE identifier = ? AND is_active = 1 LIMIT 1'):format(Tbl('civilians')),
        { identifier },
        function(rows)
            if not rows or #rows == 0 then
                NotifyClient(src, 'Register as a civilian first.', 'error')
                return
            end

            local civ = rows[1]

            -- Check for existing gun license
            MySQL.query(('SELECT * FROM %s WHERE civilian_id = ? AND type = ? AND status = ?'):format(Tbl('licenses')),
                { civ.id, 'weapon', 'VALID' },
                function(existing)
                    if existing and #existing > 0 then
                        NotifyClient(src, 'You already have a valid gun license.', 'error')
                        return
                    end

                    -- Check driver's license prerequisite
                    MySQL.query(('SELECT * FROM %s WHERE civilian_id = ? AND type = ? AND status = ?'):format(Tbl('licenses')),
                        { civ.id, 'drivers', 'VALID' },
                        function(dl)
                            if not dl or #dl == 0 then
                                NotifyClient(src, 'You need a valid driver\'s license first.', 'error')
                                return
                            end

                            local licNum = 'GL' .. tostring(os.time()):sub(-8) .. math.random(10,99)
                            MySQL.insert(('INSERT INTO %s (civilian_id, type, number, status, issued_at, expires_at) VALUES (?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR))'):format(Tbl('licenses')),
                                { civ.id, 'weapon', licNum, 'VALID' })
                            NotifyClient(src, 'Gun license issued! License: ' .. licNum, 'success')
                        end
                    )
                end
            )
        end
    )
end)

-- ============================================================
-- Insurance
-- ============================================================
RegisterNetEvent('cad:insurance:apply')
AddEventHandler('cad:insurance:apply', function(data)
    local src = source
    local identifier = data.identifier

    MySQL.query(('SELECT * FROM %s WHERE identifier = ? AND is_active = 1 LIMIT 1'):format(Tbl('civilians')),
        { identifier },
        function(rows)
            if not rows or #rows == 0 then
                NotifyClient(src, 'Register as a civilian first.', 'error')
                return
            end

            local civ = rows[1]
            MySQL.query(('SELECT * FROM %s WHERE plate = ? AND owner_id = ?'):format(Tbl('vehicles')),
                { string.upper(data.plate), civ.id },
                function(vehicles)
                    if not vehicles or #vehicles == 0 then
                        NotifyClient(src, 'Vehicle not found or not registered to you.', 'error')
                        return
                    end

                    MySQL.update(('UPDATE %s SET insurance_status = ? WHERE id = ?'):format(Tbl('vehicles')),
                        { 'VALID', vehicles[1].id })
                    NotifyClient(src, 'Insurance activated for ' .. vehicles[1].plate, 'success')
                end
            )
        end
    )
end)

-- ============================================================
-- BOLOs
-- ============================================================
RegisterNetEvent('cad:bolo:create')
AddEventHandler('cad:bolo:create', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    MySQL.insert(('INSERT INTO %s (type, priority, description, last_known_location, creator_identifier, target_civilian_id, target_vehicle_id, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(Tbl('bolos')),
        { data.type or 'PERSON', data.priority or 'MEDIUM', data.description, data.location, xPlayer.identifier, data.targetCivilianId, data.targetVehicleId, data.expiresAt },
        function(id)
            local bolo = { id = id, type = data.type, priority = data.priority, description = data.description }

            for plySrc, cache in pairs(PlayerDutyCache) do
                if cache.onDuty then
                    TriggerClientEvent('cad:bolo:alert', plySrc, bolo)
                end
            end
        end
    )
end)

-- ============================================================
-- Reports
-- ============================================================
RegisterNetEvent('cad:report:create')
AddEventHandler('cad:report:create', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local reportNumber = GenNumber(data.prefix or 'INC')
    local tblName = Tbl(data.tableName or 'incident_reports')

    MySQL.insert(('INSERT INTO %s (report_number, officer_identifier, location, date_time, type, narrative, status) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(tblName),
        { reportNumber, xPlayer.identifier, data.location, data.dateTime, data.type, data.narrative, 'DRAFT' },
        function(id)
            NotifyClient(src, 'Report created: ' .. reportNumber, 'success')
        end
    )
end)

-- ============================================================
-- Gunshot Detection
-- ============================================================
RegisterNetEvent('cad:gunfire:report')
AddEventHandler('cad:gunfire:report', function(data)
    local src = source
    if not Config.Gunfire.Enabled then return end

    -- Create dispatch call
    local callNumber = GenNumber('GUN')
    MySQL.insert(('INSERT INTO %s (call_number, type, description, location, lat, lng, priority, creator_identifier, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(Tbl('dispatch_calls')),
        { callNumber, 'SHOTS FIRED', 'Gunfire detected at ' .. (data.streetName or 'Unknown'), data.streetName or 'Unknown', data.lat, data.lng, 'PRIORITY_1', 'SYSTEM', 'PENDING' },
        function()
            -- Notify on-duty officers
            for plySrc, cache in pairs(PlayerDutyCache) do
                if cache.onDuty then
                    TriggerClientEvent('cad:gunfire:alert', plySrc, { lat = data.lat, lng = data.lng, streetName = data.streetName })
                end
            end
        end
    )
end)

-- ============================================================
-- Officer Info Request (for ID card)
-- ============================================================
RegisterNetEvent('cad:character:info')
AddEventHandler('cad:character:info', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        TriggerClientEvent('cad:character:infoResult', src, { found = false })
        return
    end

    local identifier = xPlayer.identifier

    -- Get active civilian
    MySQL.query(('SELECT * FROM %s WHERE identifier = ? AND is_active = 1 AND active = 1 LIMIT 1'):format(Tbl('civilians')),
        { identifier },
        function(civRows)
            if not civRows or #civRows == 0 then
                TriggerClientEvent('cad:character:infoResult', src, { found = false, message = 'No active character.' })
                return
            end

            local civ = civRows[1]
            local civId = civ.id

            -- Get licenses
            MySQL.query(('SELECT * FROM %s WHERE civilian_id = ?'):format(Tbl('licenses')), { civId }, function(licenses)
                -- Get vehicles
                MySQL.query(('SELECT * FROM %s WHERE owner_id = ?'):format(Tbl('vehicles')), { civId }, function(vehicles)
                    -- Get warrants
                    MySQL.query(('SELECT * FROM %s WHERE civilian_id = ? AND status = ?'):format(Tbl('warrants')), { civId, 'ACTIVE' }, function(warrants)
                        -- Counts
                        MySQL.scalar(('SELECT COUNT(*) FROM %s WHERE civilian_id = ?'):format(Tbl('citations')), { civId }, function(citationCount)
                            MySQL.scalar(('SELECT COUNT(*) FROM %s WHERE civilian_id = ?'):format(Tbl('warnings')), { civId }, function(warningCount)
                                MySQL.scalar(('SELECT COUNT(*) FROM %s WHERE civilian_id = ?'):format(Tbl('arrest_reports')), { civId }, function(arrestCount)
                                    local dob = civ.date_of_birth
                                    local dobFormatted = 'Unknown'
                                    if dob then
                                        dobFormatted = os.date('%m/%d/%Y', os.time(dob))
                                    end

                                    TriggerClientEvent('cad:character:infoResult', src, {
                                        found = true,
                                        character = {
                                            firstName = civ.firstname,
                                            lastName = civ.lastname,
                                            dateOfBirth = dobFormatted,
                                            gender = civ.gender or 'Not specified',
                                            address = civ.address or 'Not on file',
                                            phone = civ.phone or 'Not on file',
                                            licenses = licenses or {},
                                            vehicles = vehicles or {},
                                            warrants = warrants or {},
                                            citationCount = citationCount or 0,
                                            warningCount = warningCount or 0,
                                            arrestCount = arrestCount or 0,
                                        },
                                    })
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end
    )
end)

-- ============================================================
-- Get Active Calls (for dashboard)
-- ============================================================
RegisterNetEvent('cad:dispatch:getActive')
AddEventHandler('cad:dispatch:getActive', function()
    local src = source
    MySQL.query(('SELECT * FROM %s WHERE status != ? ORDER BY created_at DESC LIMIT 50'):format(Tbl('dispatch_calls')), { 'COMPLETED' }, function(rows)
        TriggerClientEvent('cad:dispatch:activeList', src, rows or {})
    end)
end)

-- ============================================================
-- Get Units (for dashboard)
-- ============================================================
RegisterNetEvent('cad:dispatch:getUnits')
AddEventHandler('cad:dispatch:getUnits', function()
    local src = source
    MySQL.query(('SELECT * FROM %s WHERE on_duty = 1'):format(Tbl('officers')), {}, function(rows)
        TriggerClientEvent('cad:dispatch:unitList', src, rows or {})
    end)
end)

-- ============================================================
-- Search Civilians
-- ============================================================
RegisterNetEvent('cad:search:civilians')
AddEventHandler('cad:search:civilians', function(query)
    local src = source
    local search = '%' .. (query or '') .. '%'

    MySQL.query(('SELECT c.*, GROUP_CONCAT(DISTINCT l.type SEPARATOR \",\") as license_types FROM %s c LEFT JOIN %s l ON c.id = l.civilian_id WHERE c.active = 1 AND (c.firstname LIKE ? OR c.lastname LIKE ? OR c.phone LIKE ?) GROUP BY c.id LIMIT 25'):format(Tbl('civilians'), Tbl('licenses')),
        { search, search, search },
        function(rows)
            TriggerClientEvent('cad:search:results', src, { type = 'civilians', results = rows or {} })
        end
    )
end)

-- ============================================================
-- Search Vehicles
-- ============================================================
RegisterNetEvent('cad:search:vehicles')
AddEventHandler('cad:search:vehicles', function(query)
    local src = source
    local search = '%' .. string.upper(query or '') .. '%'

    MySQL.query(('SELECT v.*, c.firstname, c.lastname FROM %s v LEFT JOIN %s c ON v.owner_id = c.id WHERE v.plate LIKE ? OR v.model LIKE ? OR v.vin LIKE ? LIMIT 25'):format(Tbl('vehicles'), Tbl('civilians')),
        { search, search, search },
        function(rows)
            TriggerClientEvent('cad:search:results', src, { type = 'vehicles', results = rows or {} })
        end
    )
end)

-- ============================================================
-- Player Disconnect
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    local cache = PlayerDutyCache[src]
    if cache and cache.onDuty then
        MySQL.update(('UPDATE %s SET on_duty = 0, status = ? WHERE identifier = ?'):format(Tbl('officers')),
            { 'OFF_DUTY', cache.identifier })
    end
    PlayerDutyCache[src] = nil
end)

-- ============================================================
-- Exports
-- ============================================================
exports('GetOfficerInfo', function(source)
    return PlayerDutyCache[source] or nil
end)

exports('GetActiveCalls', function(cb)
    MySQL.query(('SELECT * FROM %s WHERE status != ? ORDER BY created_at DESC LIMIT 50'):format(Tbl('dispatch_calls')), { 'COMPLETED' }, function(rows)
        if cb then cb(rows or {}) end
    end)
end)

exports('CreateDispatchCall', function(data, cb)
    local src = data.source or 0
    local callNumber = GenNumber('CAD')

    MySQL.insert(('INSERT INTO %s (call_number, type, description, location, lat, lng, priority, creator_identifier, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(Tbl('dispatch_calls')),
        { callNumber, data.type, data.description, data.location, data.lat, data.lng, data.priority or 'PRIORITY_3', 'EXPORT', 'PENDING' },
        function(id)
            local call = { id = id, call_number = callNumber, type = data.type, description = data.description }
            for plySrc, cache in pairs(PlayerDutyCache) do
                if cache.onDuty then
                    TriggerClientEvent('cad:dispatch:newCall', plySrc, call)
                end
            end
            if cb then cb(call) end
        end
    )
end)

-- ============================================================
-- Init
-- ============================================================
if Config.Logging.Enabled then
    print('[CAD-MDT] Server initialized - Standalone ESX Legacy + oxmysql')
end
