fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Cadburry'
description 'Radio Station'
version '1.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/**/*'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/types.lua',
}

client_scripts {
    'bridge/client.lua',
    'modules/**/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- '@mysql-async/lib/MySQL.lua',
    'bridge/server.lua',
    'modules/**/server.lua',
}

dependencies {
    'ox_lib',
}

escrow_ignore {
    'bridge/**/*',
    'shared/*'
}