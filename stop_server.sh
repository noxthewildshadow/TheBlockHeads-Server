#!/bin/bash
echo "Stopping Blockheads server and cleaning up sessions..."
screen -S blockheads_server -X quit 2>/dev/null || true
screen -S blockheads_bot -X quit 2>/dev/null || true
pkill -f blockheads_server171 2>/dev/null || true
pkill -f "tail -n 0 -F" 2>/dev/null || true  # Stop the bot if it's monitoring logs
killall screen 2>/dev/null || true
echo "All Screen sessions and server processes have been stopped."
screen -ls
