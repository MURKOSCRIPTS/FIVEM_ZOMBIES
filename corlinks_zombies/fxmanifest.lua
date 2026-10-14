fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'corlinks_zombies'
author 'Corlinks Roleplay'
description 'Co-op zombie survival lobbies (/zombies)'
version '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_scripts { 'client/main.lua', 'client/zombies.lua', 'client/items.lua', 'client/pap.lua', 'client/extras.lua', 'client/shop.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/fonts/*.woff2', 'html/assets/*.png', 'html/assets/*.jpg', 'html/assets/*.ogg', 'html/assets/sfx/*.ogg' }

dependencies { 'qb-core', 'ox_inventory', 'ox_lib', 'oxmysql' }
