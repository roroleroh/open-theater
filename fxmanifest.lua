fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'roroleroh - Ares Studio'
description 'Ares Open Theater - in-world video screens with statebag sync + dev link test bench'
version '0.1.0'

shared_script '@ox_lib/init.lua'
dependency 'ox_lib'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/testbench.lua'
}

server_scripts {
    'server/main.lua'
}

-- The test bench is the resource's NUI overlay (full-screen, 2D)
ui_page 'html/testbench/index.html'

-- Screen page is loaded into a DUI (not the ui_page) but still needs to be
-- registered here so nui:// can resolve it
files {
    'html/testbench/index.html',
    'html/testbench/style.css',
    'html/testbench/script.js',
    'html/screen/index.html',
    'html/screen/style.css',
    'html/screen/script.js'
}
