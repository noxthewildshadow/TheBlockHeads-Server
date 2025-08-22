#!/bin/bash

# bot_server.sh - economy bot for TheBlockheads server
# Usage: ./bot_server.sh /path/to/console.log

ECONOMY_FILE="economy_data.json"
SCAN_INTERVAL=5
LOG_FILE=""

# Helpers to safely read/write economy JSON
ensure_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
    fi
}

# Set session_welcome_shown (0 or 1)
set_session_welcome_flag() {
    local player="$1"
    local val="$2"  # 0 or 1
    local data
    data=$(cat "$ECONOMY_FILE")
    data=$(echo "$data" | jq --arg player "$player" --argjson val "$val" '.players[$player].session_welcome_shown = $val')
    echo "$data" > "$ECONOMY_FILE"
}

# Get session_welcome_shown (returns 0 or 1)
get_session_welcome_flag() {
    local player="$1"
    local val
    val=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player" '.players[$player].session_welcome_shown // 0')
    echo "${val:-0}"
}

# Initialize economy data file if missing
initialize_economy() {
    ensure_economy
}

# Add player if not exists (initialize fields)
add_player_if_new() {
    local player_name="$1"
    ensure_economy
    local exists
    exists=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player_name" '.players | has($player)')
    if [ "$exists" = "false" ]; then
        local data
        data=$(cat "$ECONOMY_FILE")
        data=$(echo "$data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0, "purchases": [], "session_welcome_shown": 0}')
        echo "$data" > "$ECONOMY_FILE"
        give_first_time_bonus "$player_name"
        return 0
    fi
    return 1
}

give_first_time_bonus() {
    local player_name="$1"
    local now=$(date +%s)
    local time_str="$(date '+%Y-%m-%d %H:%M:%S')"
    local data
    data=$(cat "$ECONOMY_FILE")
    data=$(echo "$data" | jq --arg player "$player_name" '.players[$player].tickets = 1')
    data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_login = $time')
    data=$(echo "$data" | jq --arg player "$player_name" --arg time "$time_str" '.transactions += [{"player": $player, "type": "welcome_bonus", "tickets": 1, "time": $time}]')
    echo "$data" > "$ECONOMY_FILE"
    echo "Gave first-time bonus to $player_name"
    set_session_welcome_flag "$player_name" 1
}

grant_login_ticket() {
    local player_name="$1"
    local now=$(date +%s)
    local time_str="$(date '+%Y-%m-%d %H:%M:%S')"
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_login
    last_login=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].last_login // 0')
    last_login=${last_login:-0}
    if [ "$last_login" -eq 0 ] || [ $((now - last_login)) -ge 3600 ]; then
        local current_tickets
        current_tickets=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].tickets // 0')
        current_tickets=${current_tickets:-0}
        local new_tickets=$((current_tickets + 1))
        data=$(echo "$data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
        data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_login = $time')
        data=$(echo "$data" | jq --arg player "$player_name" --arg time "$time_str" '.transactions += [{"player": $player, "type": "login_bonus", "tickets": 1, "time": $time}]')
        echo "$data" > "$ECONOMY_FILE"
        send_server_command "$player_name, you received 1 login ticket! You now have $new_tickets tickets."
    fi
}

show_welcome_message() {
    local player="$1"
    local is_new="$2"
    local force="${3:-0}"
    local now=$(date +%s)
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_welcome
    last_welcome=$(echo "$data" | jq -r --arg player "$player" '.players[$player].last_welcome_time // 0')
    last_welcome=${last_welcome:-0}
    if [ "$force" -eq 1 ] || [ "$last_welcome" -eq 0 ] || [ $((now - last_welcome)) -ge 180 ]; then
        if [ "$is_new" = "true" ]; then
            send_server_command "Hello $player! Welcome to the server. Type !tickets to check your ticket balance."
        else
            send_server_command "Welcome back $player! Type !economy_help to see economy commands."
        fi
        data=$(cat "$ECONOMY_FILE")
        data=$(echo "$data" | jq --arg player "$player" --argjson time "$now" '.players[$player].last_welcome_time = $time')
        echo "$data" > "$ECONOMY_FILE"
        set_session_welcome_flag "$player" 1
    fi
}

show_help_if_needed() {
    local player="$1"
    local now=$(date +%s)
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_help
    last_help=$(echo "$data" | jq -r --arg player "$player" '.players[$player].last_help_time // 0')
    last_help=${last_help:-0}
    if [ "$last_help" -eq 0 ] || [ $((now - last_help)) -ge 300 ]; then
        send_server_command "$player, type !economy_help to see economy commands."
        data=$(cat "$ECONOMY_FILE")
        data=$(echo "$data" | jq --arg player "$player" --argjson time "$now" '.players[$player].last_help_time = $time')
        echo "$data" > "$ECONOMY_FILE"
    fi
}

send_server_command() {
    local msg="$1"
    if screen -S blockheads_server -X stuff "$msg$(printf \\r)" 2>/dev/null; then
        echo "Sent message: $msg"
    else
        echo "Could not send message (is server running?)"
    fi
}

has_purchased() {
    local player="$1"
    local item="$2"
    local exists
    exists=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player" --arg item "$item" '.players[$player].purchases | index($item) != null')
    [ "$exists" = "true" ] && return 0 || return 1
}

add_purchase() {
    local player="$1"
    local item="$2"
    local data
    data=$(cat "$ECONOMY_FILE")
    data=$(echo "$data" | jq --arg player "$player" --arg item "$item" '.players[$player].purchases += [$item]')
    echo "$data" > "$ECONOMY_FILE"
}

process_message() {
    local player="$1"
    local message="$2"

    # If greeting and session welcome already shown, ignore auto-greeting to avoid duplicate messages
    local session_flag
    session_flag=$(get_session_welcome_flag "$player")
    case "$message" in
        "hi"|"hello"|"Hi"|"Hello"|"hola"|"Hola")
            if [ "$session_flag" -eq 1 ]; then
                # Already welcomed this session -> do nothing for the greeting
                echo "Skipping greeting response to $player because session welcome already shown"
                return
            else
                # If not welcomed yet, send greeting (and mark session welcome)
                show_welcome_message "$player" "false" 1
                return
            fi
            ;;
        "!tickets")
            local tickets
            tickets=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player" '.players[$player].tickets // 0')
            send_server_command "$player, you have $tickets tickets."
            return
            ;;
        "!buy_mod")
            local tickets
            tickets=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player" '.players[$player].tickets // 0')
            tickets=${tickets:-0}
            if has_purchased "$player" "mod"; then
                send_server_command "$player, you already have MOD rank."
                return
            fi
            if [ "$tickets" -ge 10 ]; then
                local new_t=$((tickets-10))
                local data
                data=$(cat "$ECONOMY_FILE")
                data=$(echo "$data" | jq --arg player "$player" --argjson tickets "$new_t" '.players[$player].tickets = $tickets')
                data=$(echo "$data" | jq --arg player "$player" '.players[$player].purchases += ["mod"]')
                local time_str="$(date '+%Y-%m-%d %H:%M:%S')"
                data=$(echo "$data" | jq --arg player "$player" --arg time "$time_str" '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                echo "$data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/mod $player$(printf \\r)"
                send_server_command "Congratulations $player! You have been promoted to MOD for 10 tickets. Remaining tickets: $new_t"
            else
                send_server_command "$player, you need $((10 - tickets)) more tickets to buy MOD rank."
            fi
            return
            ;;
        "!buy_admin")
            local tickets
            tickets=$(cat "$ECONOMY_FILE" | jq -r --arg player "$player" '.players[$player].tickets // 0')
            tickets=${tickets:-0}
            if has_purchased "$player" "admin"; then
                send_server_command "$player, you already have ADMIN rank."
                return
            fi
            if [ "$tickets" -ge 20 ]; then
                local new_t=$((tickets-20))
                local data
                data=$(cat "$ECONOMY_FILE")
                data=$(echo "$data" | jq --arg player "$player" --argjson tickets "$new_t" '.players[$player].tickets = $tickets')
                data=$(echo "$data" | jq --arg player "$player" '.players[$player].purchases += ["admin"]')
                local time_str="$(date '+%Y-%m-%d %H:%M:%S')"
                data=$(echo "$data" | jq --arg player "$player" --arg time "$time_str" '.transactions += [{"player": $player, "type": "purchase", "item": "admin", "tickets": -20, "time": $time}]')
                echo "$data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/admin $player$(printf \\r)"
                send_server_command "Congratulations $player! You have been promoted to ADMIN for 20 tickets. Remaining tickets: $new_t"
            else
                send_server_command "$player, you need $((20 - tickets)) more tickets to buy ADMIN rank."
            fi
            return
            ;;
        "!economy_help")
            send_server_command "Economy commands: !tickets, !buy_mod (10), !buy_admin (20)"
            return
            ;;
        *)
            # Not a known command, ignore or log
            return
            ;;
    esac
}

process_admin_command() {
    local cmd="$1"
    if [[ "$cmd" =~ ^!send_ticket\ ([a-zA-Z0-9_]+)\ ([0-9]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        local amt="${BASH_REMATCH[2]}"
        local data
        data=$(cat "$ECONOMY_FILE")
        local exists
        exists=$(echo "$data" | jq -r --arg player "$p" '.players | has($player)')
        if [ "$exists" = "false" ]; then
            echo "Player $p not found"
            return
        fi
        local cur
        cur=$(echo "$data" | jq -r --arg player "$p" '.players[$player].tickets // 0')
        cur=${cur:-0}
        local new=$((cur + amt))
        data=$(echo "$data" | jq --arg player "$p" --argjson tickets "$new" '.players[$player].tickets = $tickets')
        local time_str="$(date '+%Y-%m-%d %H:%M:%S')"
        data=$(echo "$data" | jq --arg player "$p" --arg time "$time_str" --argjson amount "$amt" '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        echo "$data" > "$ECONOMY_FILE"
        send_server_command "$p received $amt tickets from admin! Total: $new"
        return
    fi

    if [[ "$cmd" =~ ^!make_mod\ ([a-zA-Z0-9_]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/mod $p$(printf \\r)"
        send_server_command "$p has been promoted to MOD by admin!"
        return
    fi

    if [[ "$cmd" =~ ^!make_admin\ ([a-zA-Z0-9_]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/admin $p$(printf \\r)"
        send_server_command "$p has been promoted to ADMIN by admin!"
        return
    fi

    echo "Unknown admin command: $cmd"
}

# Detect if server already wrote a welcome for that player recently (checks log with timestamps)
server_sent_welcome_recently() {
    local player="$1"
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        return 1
    fi
    local player_lc
    player_lc=$(echo "$player" | tr '[:upper:]' '[:lower:]')
    # Look at most recent 400 lines for "Welcome" near player name
    if tail -n 400 "$LOG_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -qE "welcome( back)?(.{0,80})${player_lc}"; then
        return 0
    fi
    return 1
}

filter_server_log() {
    while read -r line; do
        # Filter out pure server restart noise but preserve meaningful events
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]]; then
            continue
        fi
        echo "$line"
    done
}

monitor_log() {
    LOG_FILE="$1"
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        echo "Usage: $0 /path/to/console.log (file must exist)"
        exit 1
    fi

    echo "Monitoring log: $LOG_FILE"
    local admin_pipe="/tmp/blockheads_admin_pipe"
    rm -f "$admin_pipe"
    mkfifo "$admin_pipe"

    # admin pipe reading
    while read -r admin_cmd < "$admin_pipe"; do
        process_admin_command "$admin_cmd"
    done &

    # read stdin -> admin pipe
    while read -r admin_input; do
        echo "$admin_input" > "$admin_pipe"
    done &

    declare -A welcome_shown

    # Tail + process lines
    tail -n 0 -F "$LOG_FILE" 2>/dev/null | filter_server_log | while read -r line; do
        # Player connected lines contain: "TEST - Player Connected NAME | ip | id"
        if [[ "$line" =~ Player\ Connected\ ([a-zA-Z0-9_]+)\ \| ]]; then
            local player="${BASH_REMATCH[1]}"
            echo "Connected: $player"

            # ensure exists in economy json
            local is_new="false"
            if add_player_if_new "$player"; then
                is_new="true"
            fi

            # If new player, mark session welcome shown (server handles first join and we gave bonus)
            if [ "$is_new" = "true" ]; then
                set_session_welcome_flag "$player" 1
                welcome_shown["$player"]=1
                # Don't grant ticket here (first-time bonus already granted)
                continue
            fi

            # For returning player: wait 5s so server can write its own welcome (if any)
            sleep 5

            # If server already sent welcome, mark session flag to avoid bot duplication
            if server_sent_welcome_recently "$player"; then
                echo "Server already welcomed $player; marking session flag"
                set_session_welcome_flag "$player" 1
                welcome_shown["$player"]=1
            else
                # Force send welcome so the player receives it without interacting
                show_welcome_message "$player" "false" 1
                welcome_shown["$player"]=1
            fi

            # Grant login ticket for returning players
            grant_login_ticket "$player"
            continue
        fi

        # Player disconnect detection: "TEST - Player Disconnected NAME"
        if [[ "$line" =~ Player\ Disconnected\ ([a-zA-Z0-9_]+) ]]; then
            local player="${BASH_REMATCH[1]}"
            echo "Disconnected: $player"
            # clear session flag so next connect will welcome again
            set_session_welcome_flag "$player" 0
            unset welcome_shown["$player"]
            continue
        fi

        # Chat messages detection: "NAME: message"
        if [[ "$line" =~ ^([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local player="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            # ignore server pseudo-messages
            if [[ "$player" == "SERVER" ]]; then
                continue
            fi
            # ensure player exists
            add_player_if_new "$player"
            process_message "$player" "$message"
            continue
        fi

        # If none matched, continue
    done

    # Cleanup
    rm -f "$admin_pipe"
    wait
}

# Main
if [ $# -eq 1 ]; then
    initialize_economy
    monitor_log "$1"
else
    echo "Usage: $0 <server_console_log>"
    exit 1
fi
