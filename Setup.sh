#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
HOME_DIR=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "================================================================"
echo "The Blockheads Linux Server Installer"
echo "================================================================"

echo "[1/6] Installing required packages..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch-dev patchelf wget jq screen libicu70
} > /dev/null 2>&1

echo "[2/6] Downloading server..."
wget -q --show-progress "$SERVER_URL" -O "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
    echo "ERROR: Failed to download server file"
    exit 1
fi

echo "[3/6] Extracting files..."
tar xzf "$TEMP_FILE" -C .
chmod +x "$SERVER_BINARY"

echo "[4/6] Configuring library compatibility..."
# Check if binary exists before patching
if [ ! -f "$SERVER_BINARY" ]; then
    echo "ERROR: Server binary not found after extraction"
    exit 1
fi

patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY" 2>/dev/null || true

echo "[5/6] Creating start script..."
cat > start.sh << 'EOF'
#!/bin/bash

world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=12153

log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="./blockheads_server171"

# Change to script directory
cd "$(dirname "$0")"

# Clean up any existing screen sessions
screen -S blockheads -X quit 2>/dev/null || true

# Check and create log directory
if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
fi

if [ ! -f "$server_binary" ]; then
    echo "Error: Cannot find server executable $server_binary"
    exit 1
fi

if [ ! -x "$server_binary" ]; then
    chmod +x "$server_binary"
fi

echo "========================================"
echo "    The Blockheads Server"
echo "========================================"
echo "World ID: $world_id"
echo "Port: $server_port"
echo "Logs: $log_file"
echo "========================================"
echo "Server starting in 3 seconds..."
sleep 3

restart_count=0
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Starting server (restart #$restart_count)" | tee -a "$log_file"
    
    # Run server in the background
    $server_binary -o "$world_id" -p "$server_port" >> "$log_file" 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to exit
    wait $SERVER_PID
    exit_code=$?
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Server closed (exit code: $exit_code), restarting in 3s..." | tee -a "$log_file"
    sleep 3
done
EOF

echo "[6/6] Creating bot server script..."
cat > bot_server.sh << 'EOF'
#!/bin/bash

ECONOMY_FILE="economy_data.json"

# Change to script directory
cd "$(dirname "$0")"

initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "Economy data file created."
    fi
}

add_player_if_new() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
    
    if [ "$player_exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_help_time": 0}')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added new player: $player_name"
        give_first_time_bonus "$player_name"
    fi
}

give_first_time_bonus() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local current_time=$(date +%s)
    
    current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player].tickets = 1')
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_login = $time')
    
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
        '.transactions += [{"player": $player, "type": "first_time_bonus", "tickets": 1, "time": $time}]')
    
    echo "$current_data" > "$ECONOMY_FILE"
    echo "Gave first-time bonus to $player_name"
    send_server_command "say Welcome $player_name! You received 1 ticket as a first-time bonus. Type !economy_help for info."
}

grant_login_ticket() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    
    local last_login=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_login')
    
    if [ "$last_login" -eq 0 ] || [ $((current_time - last_login)) -ge 3600 ]; then
        local current_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
        local new_tickets=$((current_tickets + 1))
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
            '.players[$player].tickets = $tickets')
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" \
            '.players[$player].last_login = $time')
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
            '.transactions += [{"player": $player, "type": "login_bonus", "tickets": 1, "time": $time}]')
        
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Granted 1 ticket to $player_name for logging in (Total: $new_tickets)"
        send_server_command "say $player_name, you received 1 login ticket! You now have $new_tickets tickets."
    else
        local next_login=$((last_login + 3600))
        local time_left=$((next_login - current_time))
        echo "$player_name must wait $((time_left / 60)) minutes for next ticket"
    fi
}

show_help_if_needed() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    local last_help_time=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_help_time')
    
    if [ "$last_help_time" -eq 0 ] || [ $((current_time - last_help_time)) -ge 300 ]; then
        send_server_command "say $player_name, type !economy_help to see economy commands."
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_help_time = $time')
        echo "$current_data" > "$ECONOMY_FILE"
    fi
}

send_server_command() {
    local command="$1"
    
    # Try to send command via screen
    if screen -S blockheads -X stuff "$command$(printf \\r)" 2>/dev/null; then
        echo "Sent command to server: $command"
    else
        echo "Warning: Could not send command to server. Is the server running in screen?"
        echo "Command: $command"
    fi
}

process_message() {
    local player_name="$1"
    local message="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
    
    case "$message" in
        "hi"|"hello"|"Hi"|"Hello"|"hey"|"Hey")
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
            send_server_command "say Economy commands: !tickets (check balance), !buy_mod (10 tickets for MOD), !buy_admin (20 tickets for ADMIN)"
            ;;
    esac
}

process_admin_command() {
    local command="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    
    if [[ "$command" =~ ^!send_ticket\ ([a-zA-Z0-9_]+)\ ([0-9]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        local tickets_to_add="${BASH_REMATCH[2]}"
        
        local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
        if [ "$player_exists" = "false" ]; then
            echo "Player $player_name not found in economy system."
            return
        fi
        
        local current_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
        local new_tickets=$((current_tickets + tickets_to_add))
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
            '.players[$player].tickets = $tickets')
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" --argjson amount "$tickets_to_add" \
            '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added $tickets_to_add tickets to $player_name (Total: $new_tickets)"
        send_server_command "say $player_name received $tickets_to_add tickets from admin! Total: $new_tickets"
    else
        echo "Unknown admin command: $command"
    fi
}

filter_server_log() {
    while read line; do
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]]; then
            continue
        fi
        echo "$line"
    done
}

monitor_log() {
    local log_file="$1"
    echo "========================================"
    echo "     The Blockheads Economy Bot"
    echo "========================================"
    echo "Monitoring: $log_file"
    echo "Player commands: !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "Admin commands: !send_ticket <player> <amount>"
    echo "========================================"
    echo "To send admin commands, type them below:"
    
    while read -r admin_command; do
        if [[ "$admin_command" == "!send_ticket "* ]]; then
            process_admin_command "$admin_command"
        elif [[ "$admin_command" == "quit" ]]; then
            echo "Stopping bot..."
            exit 0
        else
            echo "Unknown admin command. Use: !send_ticket <player> <amount>"
        fi
    done &
    
    tail -n 0 -F "$log_file" | filter_server_log | while read line; do
        if [[ "$line" =~ ([a-zA-Z0-9_]+)\ connected\.$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            echo "Player connected: $player_name"
            add_player_if_new "$player_name"
            grant_login_ticket "$player_name"
            show_help_if_needed "$player_name"
            continue
        fi
        
        if [[ "$line" =~ ([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            echo "Chat: $player_name: $message"
            add_player_if_new "$player_name"
            process_message "$player_name" "$message"
            continue
        fi
        
        if [[ "$line" =~ Console:\ (!send_ticket\ [a-zA-Z0-9_]+\ [0-9]+) ]]; then
            local admin_command="${BASH_REMATCH[1]}"
            echo "Admin command from console: $admin_command"
            process_admin_command "$admin_command"
            continue
        fi
    done
}

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

chown "$ORIGINAL_USER:$ORIGINAL_USER" start.sh "$SERVER_BINARY" bot_server.sh
chmod 755 start.sh "$SERVER_BINARY" bot_server.sh

sudo -u "$ORIGINAL_USER" bash -c 'echo "{\"players\": {}, \"transactions\": []}" > economy_data.json'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json

rm -f "$TEMP_FILE"

echo "================================================================"
echo "Installation completed successfully!"
echo "================================================================"
echo "To see server commands: ./blockheads_server171 --help"
echo ""
echo "To start the server:"
echo "  screen -S blockheads ./start.sh"
echo ""
echo "To start the economy bot:"
echo "  ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log"
echo ""
echo "To stop everything:"
echo "  pkill -f blockheads_server171"
echo "================================================================"
echo "Economy System Features:"
echo "  - First-time players get 1 ticket immediately"
echo "  - Players get 1 ticket every hour when they connect"
echo "  - Commands: !tickets, !buy_mod (10), !buy_admin (20)"
echo "  - Admin commands: !send_ticket <player> <amount>"
echo "================================================================"
echo "Verifying executable..."
if sudo -u "$ORIGINAL_USER" ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Status: Executable verified successfully"
else
    echo "Warning: The executable might have compatibility issues"
    echo "You may need to manually install additional dependencies"
fi
echo "================================================================"
