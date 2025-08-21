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

# Function to check if player is in mod/admin list
is_player_in_list() {
    local player_name="$1"
    local list_type="$2"
    
    # Get world directory from log file path
    local world_dir=$(dirname "$LOG_FILE")
    local list_file="$world_dir/${list_type}list.txt"
    
    # Convert player name to lowercase (as stored in the lists)
    local lower_player_name=$(echo "$player_name" | tr '[:upper:]' '[:lower:]')
    
    if [ -f "$list_file" ]; then
        if grep -q "^$lower_player_name$" "$list_file"; then
            return 0  # Player found in list
        fi
    fi
    
    return 1  # Player not found in list
}

# Add player to economy system if not exists
add_player_if_new() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
    
    if [ "$player_exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0, "purchases": []}')
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
            send_server_command "Hello $player_name! Welcome to the server. Type !tickets to check your ticket balance."
        else
            send_server_command "Welcome back $player_name! Type !economy_help to see economy commands."
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

# Check if player has already purchased an item
has_purchased() {
    local player_name="$1"
    local item="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    local has_item=$(echo "$current_data" | jq --arg player "$player_name" --arg item "$item" '.players[$player].purchases | index($item) != null')
    
    if [ "$has_item" = "true" ]; then
        return 0  # Player has purchased this item
    else
        return 1  # Player has not purchased this item
    fi
}

# Add purchase to player's record
add_purchase() {
    local player_name="$1"
    local item="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg item "$item" '.players[$player].purchases += [$item]')
    echo "$current_data" > "$ECONOMY_FILE"
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
            # Check if player already has MOD rank
            if has_purchased "$player_name" "mod" || is_player_in_list "$player_name" "mod"; then
                send_server_command "$player_name, you already have MOD rank. No need to purchase again."
            elif [ "$player_tickets" -ge 10 ]; then
                local new_tickets=$((player_tickets - 10))
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
                    '.players[$player].tickets = $tickets')
                
                # Add purchase record
                add_purchase "$player_name" "mod"
                
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
            # Check if player already has ADMIN rank
            if has_purchased "$player_name" "admin" || is_player_in_list "$player_name" "admin"; then
                send_server_command "$player_name, you already have ADMIN rank. No need to purchase again."
            elif [ "$player_tickets" -ge 20 ]; then
                local new_tickets=$((player_tickets - 20))
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
                    '.players[$player].tickets = $tickets')
                
                # Add purchase record
                add_purchase "$player_name" "admin"
                
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
        
        # Skip server-generated welcome messages to avoid duplicates
        if [[ "$line" == *"SERVER: say"*"Welcome"* ]] || [[ "$line" == *"SERVER: say"*"received"*"ticket"*"welcome bonus"* ]]; then
            continue
        fi
        
        # Output only relevant lines
        echo "$line"
    done
}

# Monitor server log
monitor_log() {
    local log_file="$1"
    # Store log file path globally for list checking
    LOG_FILE="$log_file"
    
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
    
    # Track if we've already shown welcome for this session
    declare -A welcome_shown
    
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
            
            # For new players, the server automatically sends welcome messages
            # For returning players, we'll show a welcome message and grant login ticket
            if [ "$is_new_player" = "true" ]; then
                # Server will handle the welcome message for new players
                echo "New player $player_name connected - server will handle welcome message"
                welcome_shown["$player_name"]=1
            else
                # Only show welcome message if not shown in this session
                if [ -z "${welcome_shown[$player_name]}" ]; then
                    show_welcome_message "$player_name" "$is_new_player"
                    welcome_shown["$player_name"]=1
                fi
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
            # Remove from welcome shown tracking
            unset welcome_shown["$player_name"]
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
