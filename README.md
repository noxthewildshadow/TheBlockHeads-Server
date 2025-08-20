# TheBlockHeads-Server 2025
New launcher for TheBlockHeads server on linux

Easy install (just copy and paste):

curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/install.sh | sudo bash



Start server

screen -S blockheads -d -m ./start.sh

screen -ls

screen -r blockheads


Start server bot

./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/YOUR_WORLD_ID/console.log
