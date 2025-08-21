# TheBlockHeads-Server 2025
New launcher for TheBlockHeads server on linux

Easy install (just copy and paste):

curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/Setup.sh | sudo bash

📖 Detailed Instructions
Step 1: Installation
Download the setup script to your server

Make it executable: chmod +x setup.sh

Run with sudo: sudo ./setup.sh

The setup script will:

Install required dependencies

Download The Blockheads server files

Apply compatibility patches

Create three executable scripts: start.sh, bot_server.sh, and stop_server.sh

Set up the economy data file

Step 2: Starting the Server
The server must be run in a screen session to allow the bot to communicate with it:

bash
screen -S blockheads -d -m ./start.sh
To view the server console:

bash
screen -r blockheads
To detach from the console (without stopping the server):

Press Ctrl+A then D

Step 3: Using the Economy Bot
The economy bot adds a ticket-based system to your server:

Start the bot in a separate terminal:

bash
./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log
Players automatically receive:

1 ticket when they first join

1 ticket every hour they're connected

Player commands:

hi, hello, hola - Get a welcome message

!tickets - Check your ticket balance

!buy_mod - Buy MOD rank (10 tickets)

!buy_admin - Buy ADMIN rank (20 tickets)

!economy_help - Show economy commands

Admin commands (type in the bot terminal):

!send_ticket <player> <amount> - Give tickets to a player

Step 4: Stopping the Server
To cleanly stop everything:

bash
./stop_server.sh
This will:

Stop the server

Stop the bot

Clean up all screen sessions

🔧 Troubleshooting
Common Issues
Screen session already exists

bash
killall screen
Server executable has compatibility issues

Try running: ./blockheads_server171 --help

If it doesn't work, check that all dependencies are installed

Bot can't communicate with server

Make sure the server is running in a screen session named "blockheads"

Verify the log file path is correct

Port 15151 is already in use

Check if another process is using the port: netstat -tlnp | grep :15151

Stop the conflicting process or change the server port in start.sh

File Locations
Server executable: ./blockheads_server171

Server logs: ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log

Economy data: ./economy_data.json

Scripts: ./start.sh, ./bot_server.sh, ./stop_server.sh
