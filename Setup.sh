#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Get the original user who invoked sudo
ORIGINAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

# Configuration variables
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "================================================================"
echo "The Blockheads Linux Server Installer"
echo "================================================================"

# Install system dependencies
echo "[1/7] Installing required packages..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen
} > /dev/null 2>&1

echo "[2/7] Downloading server..."
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Failed to download server file."
    echo "Please check your internet connection and try again."
    exit 1
fi

echo "[3/7] Extracting files..."
if ! tar xzf "$TEMP_FILE" -C .; then
    echo "ERROR: Failed to extract server files."
    echo "The downloaded file may be corrupted."
    exit 1
fi

# Check if the server binary exists and has the correct name
if [ ! -f "$SERVER_BINARY" ]; then
    echo "WARNING: $SERVER_BINARY not found. Searching for alternative binary names..."
    # Look for any executable file that might be the server
    ALTERNATIVE_BINARY=$(find . -name "*blockheads*" -type f -executable | head -n 1)
    
    if [ -n "$ALTERNATIVE_BINARY" ]; then
        echo "Found alternative binary: $ALTERNATIVE_BINARY"
        SERVER_BINARY=$(basename "$ALTERNATIVE_BINARY")
        # Rename to the expected name
        mv "$ALTERNATIVE_BINARY" "blockheads_server171"
        echo "Renamed to: blockheads_server171"
    else
        echo "ERROR: Could not find the server binary."
        echo "Contents of the downloaded archive:"
        tar -tzf "$TEMP_FILE"
        exit 1
    fi
fi

chmod +x "$SERVER_BINARY"

echo "[4/7] Configuring library compatibility..."
# Verify the binary exists before applying patches
if [ ! -f "$SERVER_BINARY" ]; then
    echo "ERROR: Cannot find server binary $SERVER_BINARY for patching."
    exit 1
fi

# Apply library compatibility patches one by one with error checking
echo "Applying library patches..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY" || echo "Warning: libgnustep-base patch may have failed"
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY" || echo "Warning: libobjc patch may have failed"
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY" || echo "Warning: libgnutls patch may have failed"
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY" || echo "Warning: libgcrypt patch may have failed"
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY" || echo "Warning: libffi patch may have failed"
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY" || echo "Warning: libicui18n patch may have failed"
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY" || echo "Warning: libicuuc patch may have failed"
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY" || echo "Warning: libicudata patch may have failed"
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY" || echo "Warning: libdispatch patch may have failed"

echo "Library compatibility patches applied (some warnings may be normal)"

echo "[5/7] Creating start script..."
cat > start.sh << 'EOF'
#!/bin/bash

# Configurable settings - USER MUST CHANGE THESE!
world_id="HERE_YOUR_WORLD_ID"
server_port=12153

# Directories and paths
log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="./blockheads_server171"

# Check and create log directory
if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
fi

# Verify the server executable exists
if [ ! -f "$server_binary" ]; then
    echo "Error: Cannot find server executable $server_binary"
    exit 1
fi

# Ensure execute permissions
if [ ! -x "$server_binary" ]; then
    chmod +x "$server_binary"
fi

echo "================================================================"
echo "Starting The Blockheads Server"
echo "================================================================"
echo "World ID: $world_id (Change this in start.sh if needed)"
echo "Port: $server_port"
echo "Logs: $log_file"
echo ""
echo "IMPORTANT FOR NEW WORLDS:"
echo "1. If this is your first time, you need to create a world first!"
echo "2. Join the server from your game to generate the world"
echo "3. Stop the server with Ctrl+C once the world is created"
echo "4. Edit start.sh to change 'HERE_YOUR_WORLD_ID' to your actual world ID"
echo "5. Restart the server"
echo ""
echo "To stop the server: Press Ctrl+C"
echo "================================================================"

# Function to clean up on exit
cleanup() {
    echo ""
    echo "Server stopped. Logs saved to: $log_file"
    exit 0
}

trap cleanup INT TERM

restart_count=0
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Starting server (restart #$restart_count)" | tee -a "$log_file"
    
    # Run server with real-time log output
    $server_binary -o "$world_id" -p "$server_port" 2>&1 | tee -a "$log_file"
    
    exit_code=${PIPESTATUS[0]}
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Server closed (exit code: $exit_code), restarting in 3s..." | tee -a "$log_file"
    sleep 3
done
EOF

echo "[6/7] Creating bot server script..."
cat > bot_server.sh << 'EOF'
#!/bin/bash

# Bot configuration
ECONOMY_FILE="economy_data.json"
SCAN_INTERVAL=5

# Initialize economy data file if it doesn't exist
initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "Economy data file created."
    fi
}

# Add player to economy system if not exists
add_player_if_new() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
    
    if [ "$player_exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0}')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added new player: $player_name"
        
        # Give first-time bonus
        give_first_time_bonus "$player_name"
        return 0  # New player
    fi
    return 1  # Existing player
}

# Give first-time bonus to new players
give_first_time_bonus() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local current_time=$(date +%s)
    
    # Give 1 ticket to new player
    current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player].tickets = 1')
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_login = $time')
    
    # Add transaction record
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
        '.transactions += [{"player": $player, "type": "welcome_bonus", "tickets": 1, "time": $time}]')
    
    echo "$current_data" > "$ECONOMY_FILE"
    echo "Gave first-time bonus to $player_name"
}

# Grant login ticket (once per hour)
grant_login_ticket() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    
    # Get last login time
    local last_login=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_login')
    
    # Check if enough time has passed (1 hour = 3600 seconds)
    if [ "$last_login" -eq 0 ] || [ $((current_time - last_login)) -ge 3600 ]; then
        # Grant ticket
        local current_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
        local new_tickets=$((current_tickets + 1))
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
            '.players[$player].tickets = $tickets')
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" \
            '.players[$player].last_login = $time')
        
        # Add transaction record
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
            '.transactions += [{"player": $player, "type": "login_bonus", "tickets": 1, "time": $time}]')
        
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Granted 1 ticket to $player_name for logging in (Total: $new_tickets)"
        
        # Send message to player
        send_server_command "$player_name, you received 1 login ticket! You now have $new_tickets tickets."
    else
        local next_login=$((last_login + 3600))
        local time_left=$((next_login - current_time))
        echo "$player_name must wait $((time_left / 60)) minutes for next ticket"
    fi
}

# Show welcome message with cooldown (3 minutes)
show_welcome_message() {
    local player_name="$1"
    local is_new_player="$2"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    local last_welcome_time=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_welcome_time')
    
    # Check if enough time has passed (3 minutes = 180 seconds)
    if [ "$last_welcome_time" -eq 0 ] || [ $((current_time - last_welcome_time)) -ge 180 ]; then
        if [ "$is_new_player" = "true" ]; then
            send_server_command "Welcome $player_name! You received 1 ticket as a welcome bonus. Type !economy_help for info."
        else
            send_server_command "Welcome $player_name! Type !economy_help to see economy commands."
        fi
        
        # Update last_welcome_time
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_welcome_time = $time')
        echo "$current_data" > "$ECONOMY_FILE"
    fi
}

# Show help message if needed (5 minutes cooldown)
show_help_if_needed() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    local last_help_time=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_help_time')
    
    if [ "$last_help_time" -eq 0 ] || [ $((current_time - last_help_time)) -ge 300 ]; then
        send_server_command "$player_name, type !economy_help to see economy commands."
        # Update last_help_time
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_help_time = $time')
        echo "$current_data" > "$ECONOMY_FILE"
    fi
}

# Send command to server using screen
send_server_command() {
    local message="$1"
    
    # Send message directly without "say" prefix
    if screen -S blockheads -X stuff "$message$(printf \\r)" 2>/dev/null; then
        echo "Sent message to server: $message"
    else
        echo "Error: Could not send message to server. Is the server running in a screen session named 'blockheads'?"
        echo "Start the server with: screen -S blockheads -d -m ./start.sh"
    fi
}

# Process player message
process_message() {
    local player_name="$1"
    local message="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
    
    case "$message" in
        "hi"|"hello"|"Hi"|"Hello"|"hola"|"Hola")
            send_server_command "Hello $player_name! Welcome to the server. Type !tickets to check your ticket balance."
            ;;
        "!tickets")
            send_server_command "$player_name, you have $player_tickets tickets."
            ;;
        "!buy_mod")
            if [ "$player_tickets" -ge 10 ]; then
                local new_tickets=$((player_tickets - 10))
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
                    '.players[$player].tickets = $tickets')
                
                # Add transaction record
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
                    '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                
                echo "$current_data" > "$ECONOMY_FILE"
                
                # Apply MOD rank to player using console command format
                screen -S blockheads -X stuff "/mod $player_name$(printf \\r)"
                send_server_command "Congratulations $player_name! You have been promoted to MOD for 10 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "$player_name, you need $((10 - player_tickets)) more tickets to buy MOD rank."
            fi
            ;;
        "!buy_admin")
            if [ "$player_tickets" -ge 20 ]; then
                local new_tickets=$((player_tickets - 20))
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
                    '.players[$player].tickets = $tickets')
                
                # Add transaction record
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
                    '.transactions += [{"player": $player, "type": "purchase", "item": "admin", "tickets": -20, "time": $time}]')
                
                echo "$current_data" > "$ECONOMY_FILE"
                
                # Apply ADMIN rank to player using console command format
                screen -S blockheads -X stuff "/admin $player_name$(printf \\r)"
                send_server_command "Congratulations $player_name! You have been promoted to ADMIN for 20 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "$player_name, you need $((20 - player_tickets)) more tickets to buy ADMIN rank."
            fi
            ;;
        "!economy_help")
            send_server_command "Economy commands: !tickets (check your tickets), !buy_mod (10 tickets for MOD), !buy_admin (20 tickets for ADMIN)"
            ;;
    esac
}

# Process admin command from console
process_admin_command() {
    local command="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    
    if [[ "$command" =~ ^!send_ticket\ ([a-zA-Z0-9_]+)\ ([0-9]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        local tickets_to_add="${BASH_REMATCH[2]}"
        
        # Check if player exists
        local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
        if [ "$player_exists" = "false" ]; then
            echo "Player $player_name not found in economy system."
            return
        fi
        
        # Add tickets
        local current_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
        local new_tickets=$((current_tickets + tickets_to_add))
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
            '.players[$player].tickets = $tickets')
        
        # Add transaction record
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" --argjson amount "$tickets_to_add" \
            '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added $tickets_to_add tickets to $player_name (Total: $new_tickets)"
        send_server_command "$player_name received $tickets_to_add tickets from admin! Total: $new_tickets"
        
    elif [[ "$command" =~ ^!make_mod\ ([a-zA-Z0-9_]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        echo "Making $player_name a MOD"
        screen -S blockheads -X stuff "/mod $player_name$(printf \\r)"
        send_server_command "$player_name has been promoted to MOD by admin!"
        
    elif [[ "$command" =~ ^!make_admin\ ([a-zA-Z0-9_]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        echo "Making $player_name an ADMIN"
        screen -S blockheads -X stuff "/admin $player_name$(printf \\r)"
        send_server_command "$player_name has been promoted to ADMIN by admin!"
        
    else
        echo "Unknown admin command: $command"
        echo "Available admin commands:"
        echo "!send_ticket <player> <amount>"
        echo "!make_mod <player>"
        echo "!make_admin <player>"
    fi
}

# Filter out server restart messages
filter_server_log() {
    while read line; do
        # Skip lines with server restart messages
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]]; then
            continue
        fi
        
        # Output only relevant lines
        echo "$line"
    done
}

# Monitor server log
monitor_log() {
    local log_file="$1"
    echo "Starting economy bot. Monitoring: $log_file"
    echo "Bot commands: !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "Admin commands: !send_ticket <player> <amount>, !make_mod <player>, !make_admin <player>"
    echo "================================================================"
    echo "IMPORTANT: Admin commands must be typed in THIS terminal, NOT in the game chat!"
    echo "Type admin commands below and press Enter:"
    echo "================================================================"
    
    # Use a named pipe for admin commands to avoid blocking issues
    local admin_pipe="/tmp/blockheads_admin_pipe"
    rm -f "$admin_pipe"
    mkfifo "$admin_pipe"
    
    # Start reading from admin pipe in background
    while read -r admin_command < "$admin_pipe"; do
        echo "Processing admin command: $admin_command"
        if [[ "$admin_command" == "!send_ticket "* ]] || [[ "$admin_command" == "!make_mod "* ]] || [[ "$admin_command" == "!make_admin "* ]]; then
            process_admin_command "$admin_command"
        else
            echo "Unknown admin command. Use: !send_ticket <player> <amount>, !make_mod <player>, or !make_admin <player>"
        fi
        echo "================================================================"
        echo "Ready for next admin command:"
    done &
    
    # Also read from stdin and write to the pipe
    while read -r admin_command; do
        echo "$admin_command" > "$admin_pipe"
    done &
    
    # Monitor log file for player activity
    tail -n 0 -F "$log_file" | filter_server_log | while read line; do
        # Detect player connections (formato específico del log)
        if [[ "$line" =~ Player\ Connected\ ([a-zA-Z0-9_]+)\ \| ]]; then
            local player_name="${BASH_REMATCH[1]}"
            
            # Filtrar jugador "SERVER" y otros nombres del sistema
            if [[ "$player_name" == "SERVER" ]]; then
                echo "Ignoring system player: $player_name"
                continue
            fi
            
            echo "Player connected: $player_name"
            
            # Añadir jugador si es nuevo y determinar si es nuevo
            local is_new_player="false"
            if add_player_if_new "$player_name"; then
                is_new_player="true"
            fi
            
            # Solo mostrar mensaje de bienvenida si es nuevo jugador
            if [ "$is_new_player" = "true" ]; then
                show_welcome_message "$player_name" "$is_new_player"
            else
                grant_login_ticket "$player_name"
            fi
            continue
        fi

        # Detect player disconnections
        if [[ "$line" =~ Player\ Disconnected\ ([a-zA-Z0-9_]+) ]]; then
            local player_name="${BASH_REMATCH[1]}"
            
            # Filtrar jugador "SERVER"
            if [[ "$player_name" == "SERVER" ]]; then
                continue
            fi
            
            echo "Player disconnected: $player_name"
            continue
        fi
        
        # Detect player messages
        if [[ "$line" =~ ([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            
            # Filtrar mensajes del sistema
            if [[ "$player_name" == "SERVER" ]]; then
                echo "Ignoring system message: $message"
                continue
            fi
            
            echo "Chat: $player_name: $message"
            add_player_if_new "$player_name"
            process_message "$player_name" "$message"
            continue
        fi
        
        echo "Other log line: $line"
    done
    
    # Cleanup
    wait
    rm -f "$admin_pipe"
}

# Main execution
if [ $# -eq 1 ]; then
    initialize_economy
    monitor_log "$1"
else
    echo "Usage: $0 <server_log_file>"
    echo "Please provide the path to the server log file"
    echo "Example: ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/HERE_YOUR_WORLD_ID/console.log"
    exit 1
fi
EOF

echo "[7/7] Creating stop server script..."
cat > stop_server.sh << 'EOF'
#!/bin/bash
echo "Stopping Blockheads server and cleaning up sessions..."
screen -S blockheads -X quit 2>/dev/null
pkill -f blockheads_server171
pkill -f "tail -n 0 -F"  # Stop the bot if it's monitoring logs
killall screen 2>/dev/null
echo "All Screen sessions and server processes have been stopped."
screen -ls
EOF

# Set proper ownership and permissions
chown "$ORIGINAL_USER:$ORIGINAL_USER" start.sh "$SERVER_BINARY" bot_server.sh stop_server.sh
chmod 755 start.sh "$SERVER_BINARY" bot_server.sh stop_server.sh

# Create economy data file with proper ownership
sudo -u "$ORIGINAL_USER" bash -c 'echo "{\"players\": {}, \"transactions\": []}" > economy_data.json'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json

# Clean up
rm -f "$TEMP_FILE"

echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "To see server commands: ./blockheads_server171 --help"
echo "To start the server run: screen -S blockheads -d -m ./start.sh"
echo "To attach to server console: screen -r blockheads"
echo "To detach from console: Ctrl+A then D"
echo ""
echo "To start the economy bot run: ./bot_server.sh <path_to_log_file>"
echo ""
echo "Example for bot: ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/HERE_YOUR_WORLD_ID/console.log"
echo ""
echo "To stop everything: ./stop_server.sh"
echo ""
echo "The economy bot features:"
echo "- Players get 1 ticket every hour when they connect"
echo "- New players get 1 ticket immediately"
echo "- Commands: !tickets, !buy_mod (10), !buy_admin (20)"
echo "- Admin commands: !send_ticket <player> <amount>, !make_mod <player>, !make_admin <player>"
echo "- Economy data saved in: economy_data.json"
echo ""
echo "IMPORTANT: For the bot to work properly, you MUST:"
echo "1. Start the server in a screen session: screen -S blockheads -d -m ./start.sh"
echo "2. In a new terminal, start the bot with the correct log file path"
echo "3. To send admin commands, type them in the BOT terminal (where ./bot_server.sh is running)"
echo ""
echo "ADDITIONAL TIPS:"
echo "- If you encounter an error like 'there is already a screen with the same host', use: killall screen"
echo "- To view all active screen sessions: screen -ls"
echo "- To force close all screen sessions: killall screen"
echo "- Use ./stop_server.sh to cleanly stop everything"
echo ""
echo "Verifying executable..."
if sudo -u "$ORIGINAL_USER" ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Status: Executable verified successfully"
else
    echo "Warning: The executable might have compatibility issues"
    echo "You may need to manually install additional dependencies"
fi
echo "================================================================"
