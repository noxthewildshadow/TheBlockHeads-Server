#!/bin/bash

# =============================================================================
# The Blockheads Server Startup Script
# This script keeps the server running continuously, restarting automatically
# if it closes unexpectedly.
# =============================================================================

# Configurable settings - user can adjust these values
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151

# Directories and paths
user_home="$HOME"
log_dir="$user_home/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="/opt/blockheads-server/blockheads_server171"

# Check and create log directory if it doesn't exist
if [ ! -d "$log_dir" ]; then
    echo "Creating log directory: $log_dir"
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
    chown "$USER:$USER" "$log_dir"
fi

# Verify the server executable exists
if [ ! -f "$server_binary" ]; then
    echo "Error: Cannot find server executable $server_binary"
    echo "Please run the installation script first."
    exit 1
fi

# Ensure execute permissions on the binary
if [ ! -x "$server_binary" ]; then
    echo "Setting execute permissions on server binary..."
    chmod +x "$server_binary"
fi

echo "Starting The Blockheads Server"
echo "World: $world_id"
echo "Port: $server_port"
echo "Logs: $log_file"
echo "Use Ctrl+C to stop the server"
echo "----------------------------------------"

# Restart counter
restart_count=0

# Cleanup function for graceful shutdown
cleanup() {
    echo ""
    echo "Shutting down server..."
    kill -TERM $server_pid 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main execution loop
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] Starting server (restart #$restart_count)" >> "$log_file"
    
    # Run server and capture output
    $server_binary -o "$world_id" -p "$server_port" >> "$log_file" 2>&1 &
    server_pid=$!
    
    wait $server_pid
    
    # Log exit and prepare for restart
    exit_code=$?
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Server closed (exit code: $exit_code), restarting in 3s..." >> "$log_file"
    
    sleep 3
done
