fx_version 'cerulean'
game 'gta5'

lua54 'yes'
name 'ares-open-theater'
description 'Synced outdoor cinema screen using DUI projection'
author 'roroleroh'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'html/index.html',
    'html/app.bundle.js',
    'stream/*.ydr',
}

-- NOTE: no ui_page. This page is used ONLY as a DUI (projected onto the screen
-- surface), never as a fullscreen NUI overlay. Declaring ui_page would render
-- the page fullscreen over the player's view. DUI only needs the files above.

dependency 'ox_lib'

escrow_ignore {
    'config.lua'
}