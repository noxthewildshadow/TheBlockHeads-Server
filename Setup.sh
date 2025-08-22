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
if [ -z "$USER_HOME" ]; then
    echo "ERROR: Could not determine home directory for user '$ORIGINAL_USER'."
    exit 1
fi

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
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen lsof
} > /dev/null 2>&1

echo "[2/7] Downloading server..."
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Failed to download server file."
    echo "Please check your internet connection and try again."
    exit 1
fi

echo "[3/7] Extracting files..."
# Create a temporary directory for extraction
EXTRACT_DIR="/tmp/blockheads_extract_$$"
mkdir -p "$EXTRACT_DIR"

if ! tar xzf "$TEMP_FILE" -C "$EXTRACT_DIR"; then
    echo "ERROR: Failed to extract server files."
    echo "The downloaded file may be corrupted."
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

# Move extracted files to current directory
cp -r "$EXTRACT_DIR"/* ./
rm -rf "$EXTRACT_DIR"

# Check if the server binary exists and has the correct name
if [ ! -f "$SERVER_BINARY" ]; then
    echo "WARNING: $SERVER_BINARY not found. Searching for alternative binary names..."
    ALTERNATIVE_BINARY=$(find . -name "*blockheads*" -type f -executable | head -n 1)
    
    if [ -n "$ALTERNATIVE_BINARY" ]; then
        echo "Found alternative binary: $ALTERNATIVE_BINARY"
        SERVER_BINARY=$(basename "$ALTERNATIVE_BINARY")
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
if [ ! -f "$SERVER_BINARY" ]; then
    echo "ERROR: Cannot find server binary $SERVER_BINARY for patching."
    exit 1
fi

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

echo "[5/7] Creating unified start script..."
cat > start_server.sh << 'EOF'
#!/bin/bash

# Configuración
SERVER_BINARY="./blockheads_server171"
DEFAULT_PORT=12153
SCREEN_SERVER="blockheads_server"
SCREEN_BOT="blockheads_bot"

# Función para mostrar uso
show_usage() {
    echo "Uso: $0 start [WORLD_ID] [PORT]"
    echo "  start WORLD_ID PORT - Inicia el servidor y el bot con el mundo y puerto especificados"
    echo "  stop                - Detiene el servidor y el bot"
    echo "  status              - Muestra el estado del servidor y bot"
    echo "  help                - Muestra esta ayuda"
    echo ""
    echo "Ejemplo:"
    echo "  $0 start c1ce8d817c47daa51356cdd4ab64f032 12153"
    echo ""
    echo "Nota: Primero debes crear un mundo manualmente con:"
    echo "  ./blockheads_server171 -n"
}

# Función para verificar si el puerto está en uso
is_port_in_use() {
    local port="$1"
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null ; then
        return 0  # Puerto en uso
    else
        return 1  # Puerto libre
    fi
}

# Función para detener todo de forma segura
stop_server() {
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Deteniendo el servidor Blockheads..."
        screen -S "$SCREEN_SERVER" -X quit
    fi

    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Deteniendo el bot..."
        screen -S "$SCREEN_BOT" -X quit
    fi
    
    sleep 2

    pkill -f "$SERVER_BINARY" 2>/dev/null
    pkill -f "tail -n 0 -F" 2>/dev/null
    
    echo "Servidor y bot detenidos."
}

# Función para iniciar el servidor
start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"
    
    stop_server
    
    if is_port_in_use "$port"; then
        echo "ERROR: El puerto $port ya está en uso. No se puede iniciar el servidor."
        exit 1
    fi
    
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"

    if [ ! -d "$world_dir" ]; then
        echo "Error: El mundo '$world_id' no existe."
        echo "Primero crea un mundo con: ./blockheads_server171 -n"
        exit 1
    fi
    
    local log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
    local log_file="$log_dir/console.log"
    mkdir -p "$log_dir"
    
    echo "Iniciando servidor con mundo: $world_id, puerto: $port"
    
    screen -dmS "$SCREEN_SERVER" bash -c "
        echo 'Iniciando Blockheads server...'
        $SERVER_BINARY -o '$world_id' -p '$port' 2>&1 | tee -a '$log_file'
    "
    
    local wait_time=0
    while [ ! -f "$log_file" ] && [ $wait_time -lt 10 ]; do
        echo "Esperando por el archivo de log..."
        sleep 1
        ((wait_time++))
    done
    
    if [ ! -f "$log_file" ]; then
        echo "ERROR: No se pudo crear el archivo de log. El servidor puede no haber iniciado."
        exit 1
    fi
    
    echo "Servidor iniciado. Esperando 5 segundos para que se estabilice..."
    sleep 5
    start_bot "$log_file"
    
    echo "Servidor y bot iniciados correctamente."
    echo "Para ver la consola del servidor: screen -r $SCREEN_SERVER"
    echo "Para ver la consola del bot: screen -r $SCREEN_BOT"
}

# Función para iniciar el bot
start_bot() {
    local log_file="$1"
    
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "El bot ya está ejecutándose."
        return 0
    fi
    
    echo "Iniciando bot del servidor..."
    screen -dmS "$SCREEN_BOT" bash -c "
        echo 'Iniciando bot de economía...'
        ./bot_server.sh '$log_file'
    "
}

# Función para mostrar estado
show_status() {
    echo "=== ESTADO DEL SERVIDOR THE BLOCKHEADS ==="
    
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Servidor: EJECUTÁNDOSE"
    else
        echo "Servidor: DETENIDO"
    fi
    
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot: EJECUTÁNDOSE"
    else
        echo "Bot: DETENIDO"
    fi
    
    echo "========================================"
}

# Procesar argumentos
case "$1" in
    start)
        if [ -z "$2" ]; then
            echo "Error: Debes especificar el WORLD_ID"
            echo ""
            show_usage
            exit 1
        fi
        start_server "$2" "$3"
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

echo "[6/7] Creating improved bot server script..."
cat > bot_server.sh << 'EOF'
#!/bin/bash
set -e

# Bot configuration
ECONOMY_FILE="./economy_data.json"
declare -A WELCOME_SHOWN

# Ensure economy data file exists
initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "Economy data file created."
    fi
}

# Function to send command to server
send_server_command() {
    local message="$1"
    screen -S blockheads_server -X stuff "$message$(printf \\r)"
}

# Add player to economy system if they don't exist
add_player_if_new() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')

    if [ "$player_exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "purchases": []}')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Added new player: $player_name"
        give_first_time_bonus "$player_name"
        return 0 # New player
    fi
    return 1 # Existing player
}

# Give first-time bonus to new players
give_first_time_bonus() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local current_time=$(date +%s)
    
    current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player].tickets = 1')
    current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_login = $time')
    
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
    
    local last_login=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_login')
    
    if [ $((current_time - last_login)) -ge 3600 ]; then
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
        send_server_command "SERVER:say $player_name, you received 1 login ticket! You now have $new_tickets tickets."
    else
        local next_login=$((last_login + 3600))
        local time_left=$((next_login - current_time))
        echo "$player_name must wait $((time_left / 60)) minutes for next ticket"
    fi
}

# Process player message
process_message() {
    local player_name="$1"
    local message="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
    
    case "$message" in
        "!tickets")
            send_server_command "SERVER:say $player_name, you have $player_tickets tickets."
            ;;
        "!buy_mod")
            if [ "$player_tickets" -ge 10 ]; then
                local new_tickets=$((player_tickets - 10))
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
                    '.players[$player].tickets = $tickets')
                
                current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
                    '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                
                echo "$current_data" > "$ECONOMY_FILE"
                
                screen -S blockheads_server -X stuff "/mod $player_name$(printf \\r)"
                send_server_command "SERVER:say Congratulations $player_name! You have been promoted to MOD for 10 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "SERVER:say $player_name, you need $((10 - player_tickets)) more tickets to buy MOD rank."
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
                
                screen -S blockheads_server -X stuff "/admin $player_name$(printf \\r)"
                send_server_command "SERVER:say Congratulations $player_name! You have been promoted to ADMIN for 20 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "SERVER:say $player_name, you need $((20 - player_tickets)) more tickets to buy ADMIN rank."
            fi
            ;;
        "!economy_help")
            send_server_command "SERVER:say Economy commands: !tickets (check your tickets), !buy_mod (10 tickets for MOD), !buy_admin (20 tickets for ADMIN)"
            ;;
    esac
}

# Main execution loop
if [ $# -eq 1 ]; then
    initialize_economy
    LOG_FILE="$1"
    
    echo "Starting economy bot. Monitoring: $LOG_FILE"
    echo "Bot commands: !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "================================================================"
    
    tail -n 0 -F "$LOG_FILE" | while read line; do
        if [[ "$line" =~ Player\ Connected\ ([a-zA-Z0-9_]+)\ \| ]]; then
            local player_name="${BASH_REMATCH[1]}"
            if [ "$player_name" == "SERVER" ]; then continue; fi

            echo "Player connected: $player_name"
            
            if add_player_if_new "$player_name"; then
                send_server_command "SERVER:say Welcome $player_name! You received your first ticket. Type !tickets to check your balance."
            else
                send_server_command "SERVER:say Welcome back $player_name! Type !economy_help for commands."
                grant_login_ticket "$player_name"
            fi
            continue
        fi

        if [[ "$line" =~ Player\ Disconnected\ ([a-zA-Z0-9_]+) ]]; then
            local player_name="${BASH_REMATCH[1]}"
            if [ "$player_name" == "SERVER" ]; then continue; fi
            echo "Player disconnected: $player_name"
            continue
        fi
        
        if [[ "$line" =~ ([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            if [ "$player_name" == "SERVER" ]; then continue; fi
            
            echo "Chat: $player_name: $message"
            process_message "$player_name" "$message"
            continue
        fi
        
    done
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
screen -S blockheads_server -X quit 2>/dev/null
screen -S blockheads_bot -X quit 2>/dev/null
sleep 1
pkill -f "blockheads_server171" 2>/dev/null
pkill -f "tail -n 0 -F" 2>/dev/null
echo "All relevant Screen sessions and server processes have been stopped."
screen -ls
EOF

# Set proper ownership and permissions
chown "$ORIGINAL_USER:$ORIGINAL_USER" start_server.sh "$SERVER_BINARY" bot_server.sh stop_server.sh
chmod 755 start_server.sh "$SERVER_BINARY" bot_server.sh stop_server.sh

# Create economy data file with proper ownership
sudo -u "$ORIGINAL_USER" bash -c 'echo "{\"players\": {}, \"transactions\": []}" > economy_data.json'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json

# Clean up
rm -f "$TEMP_FILE"

echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "IMPORTANT: First create a world manually with:"
echo "  ./blockheads_server171 -n"
echo ""
echo "Then start the server and bot with:"
echo "  ./start_server.sh start WORLD_ID PORT"
echo ""
echo "Example:"
echo "  ./start_server.sh start a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6 12153"
echo ""
echo "To manage the server, use:"
echo "  ./start_server.sh status"
echo "  ./start_server.sh stop"
echo "To access the server console: screen -r blockheads_server"
echo "To access the bot console: screen -r blockheads_bot"
