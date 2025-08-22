#!/bin/bash
echo "Stopping Blockheads server and cleaning up sessions..."
screen -S blockheads_server -X quit 2>/dev/null || true
screen -S blockheads_bot -X quit 2>/dev/null || true
pkill -f "./blockheads_server171" 2>/dev/null || true
pkill -f "tail -n 0 -F" 2>/dev/null || true
killall screen 2>/dev/null || true
echo "Stopped. Active screens:"
screen -ls || true
