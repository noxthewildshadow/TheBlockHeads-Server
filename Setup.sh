#!/bin/bash
set -euo pipefail

# =====================================================
# Setup.sh - Complete installer for The Blockheads server
# Designed to run with:
#   curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/Setup.sh | sudo bash
# =====================================================

# Check running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)."
    echo "Example: curl -sSL <url> | sudo bash"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6 || echo "/home/$ORIGINAL_USER")

# Configuration
# (Bundle hosted on web archive as fallback)
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "===================================================="
echo " The Blockheads Linux Server - Automated Installer"
echo " Installing for user: $ORIGINAL_USER"
echo "===================================================="

# -----------------------
# 1) Install dependencies
# -----------------------
echo "[1/5] Installing required packages..."
apt-get update -y
# psmisc -> fuser, patchelf -> binary fixes, jq -> JSON, screen -> sessions, wget -> download
apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen psmisc || {
    echo "[WARN] Some packages failed to install automatically. Please run apt-get install manually if needed."
}
echo "[+] Dependencies installed (or already present)."

# -----------------------
# 2) Download server
# -----------------------
echo "[2/5] Downloading server bundle..."
rm -f "$TEMP_FILE"
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Failed to download the server package from $SERVER_URL"
    exit 1
fi
echo "[+] Download complete."

# -----------------------
# 3) Extract files
# -----------------------
echo "[3/5] Extracting files to $(pwd)..."
if ! tar xzf "$TEMP_FILE" -C .; then
    echo "ERROR: Extraction failed. The archive may be corrupted."
    echo "Listing archive contents for diagnosis:"
    tar -tzf "$TEMP_FILE" || true
    exit 1
fi

# If expected binary is not found, search for an executable candidate
if [ ! -f "./$SERVER_BINARY" ]; then
    echo "[!] $SERVER_BINARY not found after extraction. Searching for an executable candidate..."
    ALTERNATIVE=$(find . -maxdepth 3 -type f -executable -iname "*blockheads*" | head -n1 || true)
    if [ -n "$ALTERNATIVE" ]; then
        echo "[+] Found executable: $ALTERNATIVE"
        mv "$ALTERNATIVE" "./$SERVER_BINARY"
    else
        echo "ERROR: Could not find the server binary in the extracted archive."
        tar -tzf "$TEMP_FILE"
        exit 1
    fi
fi

chmod +x "./$SERVER_BINARY"
echo "[+] Server binary ready: ./$SERVER_BINARY"

# -----------------------
# 4) Apply compatibility patches (patchelf) - best-effort
# -----------------------
echo "[4/5] Applying compatibility patches (best-effort)..."
# These replace-needed calls are safe to attempt; failures are non-fatal.
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libffi.so.6 libffi.so.8 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "./$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libdispatch.so libdispatch.so.0 "./$SERVER_BINARY" 2>/dev/null || true
echo "[+] Patches attempted (warnings are okay)."

# -----------------------
# 5) Create helper scripts
# -----------------------
echo "[5/5] Creating helper scripts: start_server.sh, bot_server.sh, stop_server.sh ..."

# START SERVER
cat > start_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# start_server.sh
# Usage: ./start_server.sh start WORLD_ID [PORT]
#        ./start_server.sh stop
#        ./start_server.sh status

SERVER_BINARY="./blockheads_server171"
DEFAULT_PORT=12153
SCREEN_SERVER="blockheads_server"
SCREEN_BOT="blockheads_bot"

show_usage() {
    cat <<EOM
Usage: $0 start WORLD_ID [PORT]
  start WORLD_ID [PORT] - Start the server and the bot for the given world and port
  stop                  - Stop the server and the bot
  status                - Show status
  help                  - Show this help

Example:
  $0 start c1ce8d817c47daa51356cdd4ab64f032 12153

Note: Create a new world first with:
  ./blockheads_server171 -n
EOM
}

check_world_exists() {
    local world_id="$1"
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"
    if [ ! -d "$world_dir" ]; then
        echo "Error: World '$world_id' not found at: $world_dir"
        return 1
    fi
    return 0
}

# Stop only the named sessions and related processes (non-destructive)
cleanup_named_sessions() {
    # Stop named screen sessions if they exist
    screen -S "$SCREEN_BOT" -X quit 2>/dev/null || true
    screen -S "$SCREEN_SERVER" -X quit 2>/dev/null || true
    # Kill any leftover server process by binary name
    pkill -f "$SERVER_BINARY" 2>/dev/null || true
    # Optionally try to stop tails used by the bot
    pkill -f "tail -n 0 -F" 2>/dev/null || true
}

start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"

    echo "[start] Cleaning up previous named sessions (server & bot only)..."
    cleanup_named_sessions

    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Server already running (screen session found)."
        echo "To force restart: $0 stop && $0 start $world_id $port"
        return 0
    fi

    if ! check_world_exists "$world_id"; then
        return 1
    fi

    local log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
    mkdir -p "$log_dir"
    local log_file="$log_dir/console.log"

    echo "[start] Starting server for world: $world_id on port $port"
    echo "$world_id" > world_id.txt

    # Attempt to free port if in use (best-effort)
    if command -v fuser >/dev/null 2>&1; then
        fuser -k "${port}/tcp" 2>/dev/null || true
    else
        if ss -ltnp 2>/dev/null | grep -q ":${port} "; then
            ss -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p {print $6}' | cut -d',' -f2 | cut -d'=' -f2 | while read -r pid; do
                [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
            done
        fi
    fi

    screen -dmS "$SCREEN_SERVER" bash -c "
restart_count=0
while true; do
  restart_count=\$((restart_count+1))
  echo \"[server] Starting server (attempt #\$restart_count)\" | tee -a '$log_file'
  \"$SERVER_BINARY\" -o '$world_id' -p $port 2>&1 | tee -a '$log_file'
  echo '[server] Server stopped. Restarting in 3s...' | tee -a '$log_file'
  sleep 3
done
"

    # Wait for log to appear (with timeout)
    echo "[start] Waiting for log file: $log_file"
    local waited=0
    local maxwait=30
    while [ ! -f "$log_file" ] && [ $waited -lt $maxwait ]; do
        sleep 1
        waited=$((waited+1))
    done

    if [ ! -f "$log_file" ]; then
        echo "[warn] Log file did not appear in $maxwait seconds. Check server binary permissions and output."
    else
        echo "[+] Log file created: $log_file"
    fi

    start_bot "$log_file"

    echo "[start] Server and bot started. To attach to server console: screen -r $SCREEN_SERVER"
}

start_bot() {
    local log_file="$1"
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot already running."
        return 0
    fi
    sleep 5
    screen -dmS "$SCREEN_BOT" bash -c "
echo '[bot] Starting bot - monitoring: $log_file'
./bot_server.sh '$log_file'
"
    echo "Bot started in screen session: $SCREEN_BOT"
}

stop_server() {
    echo "[stop] Stopping server and bot (named sessions only)..."
    cleanup_named_sessions
    echo "[stop] Done. Check active screens with: screen -ls"
}

show_status() {
    echo "=== BLOCKHEADS STATUS ==="
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Server: RUNNING (screen: $SCREEN_SERVER)"
    else
        echo "Server: STOPPED"
    fi
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot: RUNNING (screen: $SCREEN_BOT)"
    else
        echo "Bot: STOPPED"
    fi
    if [ -f world_id.txt ]; then
        echo "Current world: $(cat world_id.txt)"
    fi
    echo "========================="
}

case "${1:-help}" in
    start)
        if [ -z "${2:-}" ]; then
            echo "Error: WORLD_ID required for start."
            show_usage
            exit 1
        fi
        start_server "$2" "${3:-}"
        ;;
    stop)
        stop_server
        ;;
    status)
        show_status
        ;;
    help|*)
        show_usage
        ;;
esac
EOF

# BOT SERVER (mejorado)
cat > bot_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# bot_server.sh (mejorado)
# Uso: ./bot_server.sh /ruta/a/console.log

ECONOMY_FILE="economy_data.json"
LOG_FILE="${1:-}"

if [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <server_log_file>"
    exit 1
fi

# --- Envío: raw (sin 'say') y chat (con 'say') ---
send_server_raw() {
    local message="$1"
    # Intenta enviar texto directo a la consola del servidor.
    screen -S blockheads_server -X stuff "$message$(printf \\r)" 2>/dev/null || {
        echo "[bot] Failed to send raw to server (is screen session running?)"
    }
}

send_server_chat() {
    local message="$1"
    # Fuerza 'say' para asegurar que aparezca en chat si el servidor lo necesita.
    screen -S blockheads_server -X stuff "say $message$(printf \\r)" 2>/dev/null || {
        echo "[bot] Failed to send chat to server (is screen session running?)"
    }
}

# Por compatibilidad, wrapper que intenta raw y si falla usa 'say'
send_server_command() {
    local message="$1"
    # Mensajes que son comandos de consola (comienzan con '/') deben enviarse raw
    if [[ "$message" =~ ^/ ]] ; then
        send_server_raw "$message"
        return
    fi
    # Por defecto usamos raw para bienvenidas y respuestas; si no funciona, admin puede cambiar a send_server_chat
    send_server_raw "$message"
}

# --- utilidades para claves consistentes ---
player_key() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "[bot] Created economy file: $ECONOMY_FILE"
    fi
}

is_player_in_list() {
    local player_name="$1"; local list_type="$2"
    local world_dir; world_dir=$(dirname "$LOG_FILE")
    local list_file="$world_dir/${list_type}list.txt"
    local lower_name; lower_name=$(player_key "$player_name")
    [ -f "$list_file" ] && grep -q "^$lower_name$" "$list_file"
}

add_player_if_new() {
    local player_name="$1"
    local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local exists; exists=$(echo "$current_data" | jq --arg player "$pkey" '.players | has($player)')
    if [ "$exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$pkey" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0, "purchases": []}')
        echo "$current_data" > "$ECONOMY_FILE"
        give_first_time_bonus "$player_name"
        return 0
    fi
    return 1
}

give_first_time_bonus() {
    local player_name="$1"
    local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local now; now=$(date +%s)
    current_data=$(echo "$current_data" | jq --arg player "$pkey" '.players[$player].tickets = 1')
    current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson time "$now" '.players[$player].last_login = $time')
    current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "welcome_bonus", "tickets": 1, "time": $time}]')
    echo "$current_data" > "$ECONOMY_FILE"
    # Bienvenida: usamos raw para no requerir 'say'
    send_server_command "Welcome $player_name! You received 1 welcome ticket."
    echo "[bot] Welcome bonus given to $player_name"
}

grant_login_ticket() {
    local player_name="$1"
    local pkey; pkey=$(player_key "$player_name")
    local now; now=$(date +%s)
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local last_login; last_login=$(echo "$current_data" | jq -r --arg player "$pkey" '.players[$player].last_login')
    if [ "$last_login" = "null" ]; then last_login=0; fi
    if [ "$last_login" -eq 0 ] || [ $((now - last_login)) -ge 3600 ]; then
        local current_tickets; current_tickets=$(echo "$current_data" | jq -r --arg player "$pkey" '.players[$player].tickets')
        current_tickets=${current_tickets:-0}
        local new_tickets=$((current_tickets + 1))
        current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
        current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson time "$now" '.players[$player].last_login = $time')
        current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "login_bonus", "tickets": 1, "time": $time}]')
        echo "$current_data" > "$ECONOMY_FILE"
        send_server_command "$player_name, you received 1 login ticket! You now have $new_tickets tickets."
    fi
}

has_purchased() {
    local player_name="$1"; local item="$2"; local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local res; res=$(echo "$current_data" | jq --arg player "$pkey" --arg item "$item" '.players[$player].purchases | index($item) != null')
    [ "$res" = "true" ]
}

add_purchase() {
    local player_name="$1"; local item="$2"; local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg item "$item" '.players[$player].purchases += [$item]')
    echo "$current_data" > "$ECONOMY_FILE"
}

process_message() {
    local player_name="$1"; local message="$2"
    local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local player_tickets; player_tickets=$(echo "$current_data" | jq -r --arg player "$pkey" '.players[$player].tickets')
    player_tickets=${player_tickets:-0}

    # Protección: si el message es extraño como "!b" (muy corto) ignorar para evitar respuestas raras
    if [[ "${message}" =~ ^![a-zA-Z]{1,2}$ ]]; then
        echo "[bot] Ignoring suspicious/short command message: $message"
        return
    fi

    case "$message" in
        hi|hello|hola|Hola|Hi|Hello)
            # Bienvenida simple: no hace falta 'say' según tu preferencia
            send_server_command "Hello $player_name! Welcome to the server. Type !tickets to check your ticket balance."
            ;;
        "!tickets")
            send_server_command "$player_name, you have $player_tickets tickets."
            ;;
        "!buy_mod")
            if has_purchased "$player_name" "mod" || is_player_in_list "$player_name" "mod"; then
                send_server_command "$player_name, you already have MOD rank. No need to purchase again."
            elif [ "$player_tickets" -ge 10 ]; then
                local new_tickets=$((player_tickets - 10))
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
                add_purchase "$player_name" "mod"
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                echo "$current_data" > "$ECONOMY_FILE"
                # El cambio de rango necesita slash; enviamos raw comando de consola ("/mod ...")
                screen -S blockheads_server -X stuff "/mod $player_name$(printf \\r)" 2>/dev/null || true
                send_server_command "Congratulations $player_name! You have been promoted to MOD for 10 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "$player_name, you need $((10 - player_tickets)) more tickets to buy MOD rank."
            fi
            ;;
        "!buy_admin")
            if has_purchased "$player_name" "admin" || is_player_in_list "$player_name" "admin"; then
                send_server_command "$player_name, you already have ADMIN rank. No need to purchase again."
            elif [ "$player_tickets" -ge 20 ]; then
                local new_tickets=$((player_tickets - 20))
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
                add_purchase "$player_name" "admin"
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "purchase", "item": "admin", "tickets": -20, "time": $time}]')
                echo "$current_data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/admin $player_name$(printf \\r)" 2>/dev/null || true
                send_server_command "Congratulations $player_name! You have been promoted to ADMIN for 20 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "$player_name, you need $((20 - player_tickets)) more tickets to buy ADMIN rank."
            fi
            ;;
        "!economy_help")
            send_server_command "Economy commands: !tickets, !buy_mod (10), !buy_admin (20)"
            ;;
    esac
}

process_admin_command() {
    local command="$1"
    local current_data; current_data=$(cat "$ECONOMY_FILE")

    if [[ "$command" =~ ^!send_ticket[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]+([0-9]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"; local tickets_to_add="${BASH_REMATCH[2]}"
        local pkey; pkey=$(player_key "$player_name")
        local player_exists; player_exists=$(echo "$current_data" | jq --arg player "$pkey" '.players | has($player)')
        if [ "$player_exists" = "false" ]; then
            echo "Player $player_name not found in economy system."
            return
        fi
        local current_tickets; current_tickets=$(echo "$current_data" | jq -r --arg player "$pkey" '.players[$player].tickets')
        current_tickets=${current_tickets:-0}
        local new_tickets=$((current_tickets + tickets_to_add))
        current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
        current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" --argjson amount "$tickets_to_add" '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added $tickets_to_add tickets to $player_name (Total: $new_tickets)"
        send_server_command "$player_name received $tickets_to_add tickets from admin! Total: $new_tickets"
    elif [[ "$command" =~ ^!make_mod[[:space:]]+([a-zA-Z0-9_]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/mod $player_name$(printf \\r)" 2>/dev/null || true
        send_server_command "$player_name has been promoted to MOD by admin!"
    elif [[ "$command" =~ ^!make_admin[[:space:]]+([a-zA-Z0-9_]+)$ ]]; then
        local player_name="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/admin $player_name$(printf \\r)" 2>/dev/null || true
        send_server_command "$player_name has been promoted to ADMIN by admin!"
    else
        echo "Unknown admin command: $command"
    fi
}

filter_server_log() {
    while read -r line; do
        # quitamos solo las líneas de arranque/restart muy evidentes (pero no "say" para no perder chats)
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]] ; then
            continue
        fi
        echo "$line"
    done
}

monitor_log() {
    echo "[bot] Monitoring: $LOG_FILE"
    echo "[bot] Commands: !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "[bot] Admin (in this terminal): !send_ticket <player> <amount>, !make_mod <player>, !make_admin <player>"
    echo "================================================================"

    local admin_pipe="/tmp/blockheads_admin_pipe_$$"
    rm -f "$admin_pipe"
    mkfifo "$admin_pipe"

    ( while read -r admin_command; do
          echo "$admin_command" > "$admin_pipe"
      done ) &

    ( while read -r admin_command < "$admin_pipe"; do
          process_admin_command "$admin_command"
      done ) &

    # welcome_shown keyed por player_key (minúsculas) para persistir entre cambios de mayúsculas
    declare -A welcome_shown

    tail -n 0 -F "$LOG_FILE" | filter_server_log | while read -r line; do
        # 1) Detección flexible de "Player connected" (varios formatos)
        if [[ "$line" =~ Player.*Connected.*([a-zA-Z0-9_]+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local pkey; pkey=$(player_key "$raw_name")
            echo "[bot] Player connected: $raw_name"
            local is_new="false"
            if add_player_if_new "$raw_name"; then
                is_new="true"
            fi
            # Si no se mostró la bienvenida (o fue reiniciado el bot), mostrarla otra vez y dar ticket
            if [ -z "${welcome_shown[$pkey]:-}" ]; then
                if [ "$is_new" = "true" ]; then
                    # Bienvenida primera vez (raw)
                    send_server_command "Welcome $raw_name! Type !economy_help to see economy commands."
                else
                    send_server_command "Welcome back $raw_name! Type !economy_help to see economy commands."
                    grant_login_ticket "$raw_name"
                fi
                welcome_shown[$pkey]=1
            fi
            continue
        fi

        # 2) Disconnect detection (liberamos el flag para que al reconectar se vuelva a dar bienvenida)
        if [[ "$line" =~ Player.*Disconnected.*([a-zA-Z0-9_]+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local pkey; pkey=$(player_key "$raw_name")
            unset welcome_shown[$pkey]
            echo "[bot] Player disconnected: $raw_name (cleared welcome flag)"
            continue
        fi

        # 3) Chat detection: "<Player>: message" en cualquier parte de la línea
        if [[ "$line" =~ ([a-zA-Z0-9_]+):[[:space:]](.+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            # Protección: si el message es corto y extraño, ignorar
            if [[ -z "$message" ]] || [[ "${message}" =~ ^![a-zA-Z]{1,2}$ ]]; then
                echo "[bot] Ignored weird chat line from $raw_name: '$message'"
                continue
            fi
            [ "$raw_name" = "SERVER" ] && continue
            add_player_if_new "$raw_name"
            process_message "$raw_name" "$message"
            continue
        fi
    done

    rm -f "$admin_pipe"
    wait
}

initialize_economy
monitor_log
EOF

# STOP SERVER
cat > stop_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "[stop] Stopping named Blockheads sessions and cleaning up..."
screen -S blockheads_server -X quit 2>/dev/null || true
screen -S blockheads_bot -X quit 2>/dev/null || true
pkill -f blockheads_server171 2>/dev/null || true
pkill -f "tail -n 0 -F" 2>/dev/null || true
echo "[stop] Done. Check running screens with: screen -ls"
EOF

# Make scripts executable and set ownership to original user
chmod 755 start_server.sh bot_server.sh stop_server.sh "./$SERVER_BINARY"
chown "$ORIGINAL_USER:$ORIGINAL_USER" start_server.sh bot_server.sh stop_server.sh "./$SERVER_BINARY" || true

# Create economy_data.json for the non-root user
sudo -u "$ORIGINAL_USER" bash -c 'cat > economy_data.json <<JSON
{"players": {}, "transactions": []}
JSON'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json || true
chmod 644 economy_data.json

# Cleanup downloaded archive
rm -f "$TEMP_FILE" || true

echo "===================================================="
echo " Installation completed."
echo " Quick start:"
echo " 1) As $ORIGINAL_USER create a world: ./blockheads_server171 -n"
echo " 2) Start the server: ./start_server.sh start WORLD_ID [PORT]"
echo " 3) Stop: ./start_server.sh stop   (or ./stop_server.sh)"
echo ""
echo "Note: The installer now only closes the named screen sessions"
echo "      'blockheads_server' and 'blockheads_bot' instead of killing all screens."
echo "===================================================="

# Basic verification attempt (non-fatal)
if sudo -u "$ORIGINAL_USER" "./$SERVER_BINARY" --help >/dev/null 2>&1; then
    echo "[OK] Server binary responds to --help."
else
    echo "[WARN] Server binary may require additional dependencies on this system."
fi

exit 0
