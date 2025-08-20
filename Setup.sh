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
echo "[1/6] Installing required packages..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen
} > /dev/null 2>&1

echo "[2/6] Downloading server..."
wget -q "$SERVER_URL" -O "$TEMP_FILE"

echo "[3/6] Extracting files..."
tar xzf "$TEMP_FILE" -C .
chmod +x "$SERVER_BINARY"

# Apply library compatibility patches
echo "[4/6] Configuring library compatibility..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY"
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY"
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY"
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY"
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY"
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY"
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY"

echo "[5/6] Creating start script..."
cat > start.sh << 'EOF'
#!/bin/bash

# Configurable settings
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151

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

echo "Starting The Blockheads Server"
echo "World: $world_id"
echo "Port: $server_port"
echo "Logs: $log_file"
echo "Use Ctrl+C to stop the server"
echo "----------------------------------------"

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

echo "[6/6] Creating bot server script..."
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
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_help_time": 0}')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added new player: $player_name"
        
        # Give first-time bonus
        give_first_time_bonus "$player_name"
    fi
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
        '.transactions += [{"player": $player, "type": "first_time_bonus", "tickets": 1, "time": $time}]')
    
    echo "$current_data" > "$ECONOMY_FILE"
    echo "Gave first-time bonus to $player_name"
    send_server_command "say Welcome $player_name! You received 1 ticket as a first-time bonus. Type !economy_help for info."
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
        send_server_command "say $player_name, you received 1 login ticket! You now have $new_tickets tickets."
    else
        local next_login=$((last_login + 3600))
        local time_left=$((next_login - current_time))
        echo "$player_name must wait $((time_left / 60)) minutes for next ticket"
    fi
}

# Show help message if needed (5 minutes cooldown)
show_help_if_needed() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    local last_help_time=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_help_time')
    
    if [ "$last_help_time" -eq 0 ] || [ $((current_time - last_help_time)) -ge 300 ]; then
        send_server_command "say $player_name, type !economy_help to see economy commands."
        # Update last_help_time
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_help_time = $time')
        echo "$current_data" > "$ECONOMY_FILE"
    fi
}

# Send command to server using screen
send_server_command() {
    local command="$1"
    
    # Try to send command via screen
    if screen -S blockheads -X stuff "$command$(printf \\r)" 2>/dev/null; then
        echo "Sent command to server: $command"
    else
        echo "Error: Could not send command to server. Is the server running in a screen session named 'blockheads'?"
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
        "hi"|"hello"|"Hi"|"Hello")
            send_server_command "say Welcome to the server, $player_name! Type !tickets to check your balance."
            ;;
        "!tickets")
            send_server_command "say $player_name, you have $player_tickets tickets."
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
                send_server_command "mod $player_name"
                send_server_command "say $player_name has been promoted to MOD for 10 tickets! Remaining tickets: $new_tickets"
            else
                send_server_command "say $player_name, you need $((10 - player_tickets)) more tickets to buy MOD rank."
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
                send_server_command "admin $player_name"
                send_server_command "say $player_name has been promoted to ADMIN for 20 tickets! Remaining tickets: $new_tickets"
            else
                send_server_command "say $player_name, you need $((20 - player_tickets)) more tickets to buy ADMIN rank."
            fi
            ;;
        "!economy_help")
            send_server_command "say Economy commands: !tickets, !buy_mod (10 tickets), !buy_admin (20 tickets)"
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
        send_server_command "say $player_name received $tickets_to_add tickets from admin! Total: $new_tickets"
    else
        echo "Unknown admin command: $command"
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
    echo "Admin commands: !send_ticket <player> <amount>"
    echo "To send admin commands, type them and press Enter:"
    
    # Start reading from stdin for admin commands
    while read -r admin_command; do
        if [[ "$admin_command" == "!send_ticket "* ]]; then
            process_admin_command "$admin_command"
        else
            echo "Unknown admin command. Use: !send_ticket <player> <amount>"
        fi
    done &
    
    # Monitor log file for player activity
    tail -n 0 -F "$log_file" | filter_server_log | while read line; do
        # Detect player connections
        if [[ "$line" =~ ([a-zA-Z0-9_]+)\ connected\.$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            echo "Player connected: $player_name"
            add_player_if_new "$player_name"
            grant_login_ticket "$player_name"
            show_help_if_needed "$player_name"
            continue
        fi
        
        # Detect player messages
        if [[ "$line" =~ ([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            echo "Chat: $player_name: $message"
            add_player_if_new "$player_name"
            process_message "$player_name" "$message"
            continue
        fi
        
        echo "Other log line: $line"
    done
}

# Main execution
if [ $# -eq 1 ]; then
    initialize_economy
    monitor_log "$1"
else
    echo "Usage: $0 <server_log_file>"
    echo "Please provide the path to the server log file"
    echo "Example: ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log"
    exit 1
fi
EOF

# Set proper ownership and permissions
chown "$ORIGINAL_USER:$ORIGINAL_USER" start.sh "$SERVER_BINARY" bot_server.sh
chmod 755 start.sh "$SERVER_BINARY" bot_server.sh

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
echo "Example for bot: ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log"
echo ""
echo "The economy bot features:"
echo "- Players get 1 ticket every hour when they connect"
echo "- First-time players get 1 ticket immediately"
echo "- Commands: !tickets, !buy_mod (10), !buy_admin (20)"
echo "- Admin commands: !send_ticket <player> <amount>"
echo "- Economy data saved in: economy_data.json"
echo ""
echo "IMPORTANT: For the bot to work properly, you MUST:"
echo "1. Start the server in a screen session: screen -S blockheads -d -m ./start.sh"
echo "2. In a new terminal, start the bot with the correct log file path"
echo "3. To send admin commands, type them in the bot terminal"
echo ""
echo "Verifying executable..."
if sudo -u "$ORIGINAL_USER" ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Status: Executable verified successfully"
else
    echo "Warning: The executable might have compatibility issues"
fi
echo "================================================================"
