-- ============================================================
-- CAD-MDT Standalone Configuration
-- ESX Legacy + oxmysql
-- ============================================================

Config = {}

-- ============================================================
-- Framework Settings
-- ============================================================
Config.Framework = 'esx'
Config.ESXExport = 'es_extended'

-- ============================================================
-- Database Table Prefix
-- ============================================================
Config.TablePrefix = 'mdtx_'

-- ============================================================
-- NUI / Tablet Settings
-- ============================================================
Config.NUI = {
    Keybind = 'f7',
    AllowWhileInVehicle = true,
    AllowOnFoot = true,
}

-- ============================================================
-- Job Settings
-- ============================================================
Config.PoliceJobs = {
    'police', 'lspd', 'bcso', 'sahp', 'sheriff',
    'trooper', 'officer', 'sergeant', 'lieutenant',
    'captain', 'chief', 'commander',
}
Config.AllowedGrade = 0

-- ============================================================
-- Dispatch Settings
-- ============================================================
Config.Dispatch = {
    Enabled = true,
    AutoAssignPriority = true,
    NotifyAllOfficers = true,
}

-- ============================================================
-- Notifications
-- ============================================================
Config.Notifications = {
    DispatchNotifications = true,
    BOLOAlerts = true,
    Sound = true,
}

-- ============================================================
-- Duty Command
-- ============================================================
Config.DutyCommand = {
    Enabled = true,
    Command = 'duty',
    RequireCallsign = true,
}

-- ============================================================
-- Emergency / 911
-- ============================================================
Config.Emergency = {
    Enabled = true,
    Command = '911',
    Cooldown = 30,
    MaxDescriptionLength = 255,
}

-- ============================================================
-- Plate Check
-- ============================================================
Config.PlateCheck = {
    Enabled = true,
    Command = 'plate',
}

-- ============================================================
-- ID Card
-- ============================================================
Config.IDCard = {
    Enabled = true,
    Keybind = 'f2',
    Duration = 0,
}

-- ============================================================
-- Gunshot Detection
-- ============================================================
Config.Gunfire = {
    Enabled = true,
    DetectionRadius = 200.0,
    BlipDuration = 60,
    BlipSprite = 110,
    BlipColor = 1,
    BlipScale = 0.8,
    Cooldown = 10,
    NotifyDispatch = true,
    IgnoredWeapons = {
        'WEAPON_UNARMED',
        'WEAPON_STUNGUN',
        'WEAPON_SNOWBALL',
        'WEAPON_BALL',
        'WEAPON_PETROLCAN',
        'WEAPON_FIREEXTINGUISHER',
    },
}

-- ============================================================
-- Location Updates
-- ============================================================
Config.Location = {
    UpdateInterval = 5000,
    OnlyWhileOnDuty = true,
}

-- ============================================================
-- NPC Locations
-- ============================================================
Config.NPCs = {
    TargetSystem = 'auto',

    DMV = {
        Enabled = true,
        Locations = {
            {
                name = "DMV - Downtown LS",
                coords = vector3(233.76, -411.67, 48.11),
                heading = 160.0,
                model = 's_m_m_linecook',
                blip = { sprite = 225, color = 3, scale = 0.8, label = 'DMV' },
            },
            {
                name = "DMV - Paleto Bay",
                coords = vector3(-282.57, 6137.95, 31.53),
                heading = 45.0,
                model = 's_m_m_linecook',
                blip = { sprite = 225, color = 3, scale = 0.8, label = 'DMV' },
            },
        },
        RegistrationCost = 500,
    },

    CivilianReg = {
        Enabled = true,
        Locations = {
            {
                name = "City Hall - ID Office",
                coords = vector3(-545.62, -204.07, 38.22),
                heading = 295.0,
                model = 's_f_y_scrubs_01',
                blip = { sprite = 498, color = 2, scale = 0.8, label = 'Civilian Registration' },
            },
        },
    },

    GunLicense = {
        Enabled = true,
        Locations = {
            {
                name = "Ammunation - Legion Square",
                coords = vector3(22.18, -1106.72, 29.8),
                heading = 175.0,
                model = 's_m_m_ammucountry',
                blip = { sprite = 110, color = 1, scale = 0.8, label = 'Gun License' },
            },
        },
    },

    Insurance = {
        Enabled = true,
        Locations = {
            {
                name = "Insurance Agent - Downtown",
                coords = vector3(-31.24, -1113.34, 26.42),
                heading = 70.0,
                model = 'a_m_y_business_03',
                blip = { sprite = 408, color = 5, scale = 0.8, label = 'Vehicle Insurance' },
            },
        },
    },
}

-- ============================================================
-- Department Config
-- ============================================================
Config.Departments = {
    { code = 'LSPD', name = 'Los Santos Police Department', color = '#3498db' },
    { code = 'BCSO', name = 'Blaine County Sheriff\'s Office', color = '#e67e22' },
    { code = 'SAHP', name = 'San Andreas Highway Patrol', color = '#2ecc71' },
    { code = 'LSFD', name = 'Los Santos Fire Department', color = '#e74c3c' },
}

-- ============================================================
-- Logging
-- ============================================================
Config.Logging = {
    Enabled = true,
    PrintToConsole = true,
}
