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
    'html/style.css',
    'html/player.js'
}

ui_page 'html/index.html'

dependency 'ox_lib'

escrow_ignore {
    'config.lua'
}