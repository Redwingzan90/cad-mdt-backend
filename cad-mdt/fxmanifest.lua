-- ============================================================
-- CAD-MDT Standalone - FiveM Resource Manifest
-- ESX Legacy + oxmysql
-- ============================================================

fx_version 'cerulean'
game 'gta5'

name 'cad-mdt'
description 'Standalone Police CAD/MDT System - ESX Legacy'
author 'CAD System'
version '2.0.0'

-- Shared
shared_scripts {
    'config.lua',
}

-- Server
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

-- Client
client_scripts {
    'client.lua',
}

-- NUI
ui_page 'web/index.html'

files {
    'web/index.html',
}
