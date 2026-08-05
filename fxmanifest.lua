fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Cadburry'
description 'Radio Station'
version '1.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/**/*',
    'config/shared.lua',
    'config/client.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
    -- Annotations only, emits no runtime code
    'shared/types.lua',
}

client_scripts {
    'bridge/client.lua',
    'modules/**/client.lua',
}

server_scripts {
    'bridge/server.lua',
    'modules/**/server.lua',
}

dependencies {
    'ox_lib',
}

escrow_ignore {
    'config/*',
    'bridge/**/*',
    'shared/*'
}
