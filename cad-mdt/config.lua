-- Police CAD/MDT System - Configuration
-- config.lua

Config = {}

-- ============================================================
-- API Settings
-- ============================================================
Config.API = {
    URL = "https://cad-mdt-backend.onrender.com", -- Backend API URL
    ServerKey = "cfxk_1kRjwnUDp7fMl0AGeWZHe_1U24R2", -- Must match backend FIVEM_SERVER_KEY
    Timeout = 10000, -- Request timeout in ms
}

-- ============================================================
-- NUI Settings
-- ============================================================
Config.NUI = {
    Enabled = true,
    Keybind = "f7", -- Key to open/close MDT
    AllowWhileInVehicle = true,
    AllowOnFoot = true, -- Allow MDT to be opened on foot
}

-- ============================================================
-- Framework Detection
-- ============================================================
-- Auto-detect framework. Supports: 'qbcore', 'esx', 'qbox', 'standalone'
Config.Framework = 'auto' -- 'auto' | 'qbcore' | 'esx' | 'qbox' | 'standalone'

-- ============================================================
-- Duty Settings
-- ============================================================
Config.Duty = {
    AutoGoOffDutyOnDisconnect = true,
    Departments = {
        { code = "LSPD", name = "Los Santos Police Department" },
        { code = "BCSO", name = "Blaine County Sheriff's Office" },
        { code = "SAHP", name = "San Andreas Highway Patrol" },
        { code = "LSFD", name = "Los Santos Fire Department" },
    },
}

-- ============================================================
-- Location Update Settings
-- ============================================================
Config.Location = {
    UpdateInterval = 5000, -- ms between location updates
    OnlyWhileOnDuty = true,
}

-- ============================================================
-- 911 Settings
-- ============================================================
Config.Emergency = {
    Enabled = true,
    Command = "911", -- In-game command to call 911
    Cooldown = 30, -- Seconds between calls
    MaxDescriptionLength = 500,
}

-- ============================================================
-- Plate Check Settings
-- ============================================================
Config.PlateCheck = {
    Enabled = true,
    Command = "plate", -- In-game command to run a plate
    UseTarget = false, -- Use target system for plate checks
    MaxDistance = 15.0, -- Max distance to check a plate
}

-- ============================================================
-- Notification Settings
-- ============================================================
Config.Notifications = {
    DispatchNotifications = true, -- Notify officers of new calls
    BOLOAlerts = true,
    WarrantAlerts = true,
    Sound = true, -- Play sound on notification
}

-- ============================================================
-- Duty Command
-- ============================================================
Config.DutyCommand = {
    Enabled = true,
    Command = "duty", -- /duty to toggle on/off duty
    RequireCallsign = true, -- Prompt for callsign when going on duty
}

-- ============================================================
-- Gunfire Detection
-- ============================================================
Config.Gunfire = {
    Enabled = true,
    DetectionRadius = 200.0, -- Radius in meters to detect gunfire
    BlipDuration = 60, -- Seconds the blip stays on the map
    BlipSprite = 110, -- Blip sprite (crosshair)
    BlipColor = 1, -- Red
    BlipScale = 0.8,
    Cooldown = 10, -- Seconds between gunfire reports from same player
    NotifyDispatch = true, -- Send dispatch call on gunfire
    OnlyNotifyPolice = true, -- Only notify on-duty officers
    IgnoredWeapons = { -- Weapons that won't trigger detection
        "WEAPON_UNARMED",
        "WEAPON_STUNGUN",
        "WEAPON_SNOWBALL",
        "WEAPON_BALL",
        "WEAPON_PETROLCAN",
        "WEAPON_FIREEXTINGUISHER",
    },
}

-- ============================================================
-- NPC Registration Locations
-- ============================================================
Config.NPCs = {
    -- Target system: 'auto' | 'ox_target' | 'qb-target' | 'none'
    -- 'auto' will detect ox_target or qb-target automatically
    TargetSystem = 'auto',

    -- DMV NPCs for vehicle registration
    DMV = {
        Enabled = true,
        Locations = {
            {
                name = "DMV - Downtown Los Santos",
                coords = vector3(233.76, -411.67, 48.11),
                heading = 160.0,
                model = "s_m_m_linecook", -- NPC model
                blip = {
                    sprite = 225, -- Clipboard sprite
                    color = 3, -- Blue
                    scale = 0.8,
                    label = "DMV - Vehicle Registration",
                },
            },
            {
                name = "DMV - Paleto Bay",
                coords = vector3(-282.57, 6137.95, 31.53),
                heading = 45.0,
                model = "s_m_m_linecook",
                blip = {
                    sprite = 225,
                    color = 3,
                    scale = 0.8,
                    label = "DMV - Vehicle Registration",
                },
            },
            {
                name = "DMV - Sandy Shores",
                coords = vector3(1702.46, 3778.95, 34.76),
                heading = 220.0,
                model = "s_m_m_linecook",
                blip = {
                    sprite = 225,
                    color = 3,
                    scale = 0.8,
                    label = "DMV - Vehicle Registration",
                },
            },
        },
        RegistrationCost = 500, -- Cost to register a vehicle (0 = free)
        InteractionDistance = 2.5,
    },
    -- Civilian Registration / ID Office
    CivilianReg = {
        Enabled = true,
        Locations = {
            {
                name = "City Hall - ID Office",
                coords = vector3(-545.62, -204.07, 38.22),
                heading = 295.0,
                model = "s_f_y_scrubs_01", -- NPC model
                blip = {
                    sprite = 498, -- Info sprite
                    color = 2, -- Green
                    scale = 0.8,
                    label = "City Hall - Civilian Registration",
                },
            },
            {
                name = "Paleto Bay - ID Office",
                coords = vector3(-273.88, 6225.53, 31.70),
                heading = 45.0,
                model = "s_f_y_scrubs_01",
                blip = {
                    sprite = 498,
                    color = 2,
                    scale = 0.8,
                    label = "City Hall - Civilian Registration",
                },
            },
        },
        InteractionDistance = 2.5,
    },

    -- Gun License Clerk
    GunLicense = {
        Enabled = true,
        Locations = {
            {
                name = "Gun Store - Los Santos",
                coords = vector3(16.27, -1106.26, 29.79),
                heading = 340.0,
                model = "s_m_m_ammucountry",
                blip = {
                    sprite = 110, -- Crosshair
                    color = 1, -- Red
                    scale = 0.8,
                    label = "Gun License Clerk",
                },
            },
            {
                name = "Gun Store - Paleto Bay",
                coords = vector3(-662.29, -935.14, 21.82),
                heading = 180.0,
                model = "s_m_m_ammucountry",
                blip = {
                    sprite = 110,
                    color = 1,
                    scale = 0.8,
                    label = "Gun License Clerk",
                },
            },
        },
        InteractionDistance = 2.5,
    },

    -- Insurance Agent
    Insurance = {
        Enabled = true,
        Locations = {
            {
                name = "Insurance Office - Downtown LS",
                coords = vector3(-267.93, -957.0, 31.22),
                heading = 205.0,
                model = "a_m_y_business_03",
                blip = {
                    sprite = 498, -- Info sprite
                    color = 5, -- Yellow
                    scale = 0.8,
                    label = "Insurance Agent",
                },
            },
            {
                name = "Insurance Office - Paleto Bay",
                coords = vector3(-318.79, 606.94, 31.46),
                heading = 220.0,
                model = "a_m_y_business_03",
                blip = {
                    sprite = 498,
                    color = 5,
                    scale = 0.8,
                    label = "Insurance Agent",
                },
            },
        },
        InteractionDistance = 2.5,
    },
}

-- ============================================================
-- ID Card Settings
-- ============================================================
Config.IDCard = {
    Enabled = true,
    Keybind = "f2", -- Key to show/hide ID card
    ShowDuration = 5000, -- How long the ID card stays on screen (ms), 0 = toggle
    ShowInVehicle = true,
    ShowOnFoot = true,
}

-- ============================================================
-- Logging
-- ============================================================
Config.Logging = {
    Enabled = true,
    PrintToConsole = true,
}
