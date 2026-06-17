-- Police CAD/MDT System - FiveM Resource
-- fxmanifest.lua

fx_version 'cerulean'
game 'gta5'

name 'cad-mdt'
description 'Police CAD/MDT System'
author 'CAD System'
version '1.0.0'

-- Shared config
shared_scripts {
    'config.lua',
}

-- Client-side scripts
client_scripts {
    'client.lua',
}

-- Server-side scripts
server_scripts {
    'server.lua',
}

-- NUI page (the Vue web UI)
ui_page 'web/index.html'

-- Include NUI files
files {
    'web/index.html',
    'web/assets/**/*',
}

-- Exports
exports {
    'GetOfficerStatus',
    'IsOfficerOnDuty',
    'GetOfficerCallsign',
}

server_exports {
    'GetOfficerInfo',
    'GetActiveCalls',
    'SubmitEmergencyCall',
    'RunPlateCheck',
}
