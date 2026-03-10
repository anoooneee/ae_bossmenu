fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author ".ano.ne."

shared_script 'config.lua'
shared_script '@ox_lib/init.lua'
shared_script '@oxmysql/lib/MySQL.lua'
server_script 'server/server.lua'
client_script 'client/client.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/script.js',
    'web/logo.png'
}
