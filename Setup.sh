#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script requiere privilegios de root."
    echo "Por favor, ejecuta con: sudo $0"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
if [ -z "$ORIGINAL_USER" ] || [ "$ORIGINAL_USER" = "root" ]; then
    echo "ERROR: No se pudo determinar el usuario original."
    echo "Por favor, ejecuta con: sudo -u tu_usuario $0"
    exit 1
fi

SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "================================================================"
echo "Instalador de Servidor The Blockheads para Linux"
echo "================================================================"

echo "[1/6] Instalando paquetes requeridos..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y software-properties-common libgnustep-base1.28 libdispatch-dev patchelf wget jq screen
} > /dev/null 2>&1

echo "[2/6] Descargando servidor..."
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Falló la descarga del servidor."
    exit 1
fi

echo "[3/6] Extrayendo archivos..."
if ! tar xzf "$TEMP_FILE" -C . --no-same-owner; then
    echo "ERROR: Falló la extracción del archivo."
    exit 1
fi

if [ ! -f "$SERVER_BINARY" ]; then
    echo "ERROR: No se encontró el binario del servidor después de la extracción."
    exit 1
fi

chmod +x "$SERVER_BINARY"

echo "[4/6] Configurando compatibilidad de bibliotecas..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY" 2>/dev/null || true
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY" 2>/dev/null || true

echo "[5/6] Creando script de inicio..."
cat > start.sh << 'EOF'
#!/bin/bash

world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=12153

log_dir="$HOME/GNUstep/Library/Application Support/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="./blockheads_server171"

cd "$(dirname "$0")"

if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
fi

if [ ! -f "$server_binary" ]; then
    echo "Error: No se encuentra el ejecutable del servidor $server_binary"
    exit 1
fi

if [ ! -x "$server_binary" ]; then
    chmod +x "$server_binary"
fi

echo "========================================"
echo "    Servidor The Blockheads"
echo "========================================"
echo "ID Mundo: $world_id"
echo "Puerto: $server_port"
echo "Logs: $log_file"
echo "========================================"
echo "Servidor iniciando en 3 segundos..."
sleep 3

restart_count=0
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Iniciando servidor (reinicio #$restart_count)" | tee -a "$log_file"
    
    $server_binary -o "$world_id" -p "$server_port" >> "$log_file" 2>&1 &
    SERVER_PID=$!
    
    wait $SERVER_PID
    exit_code=$?
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Servidor cerrado (código de salida: $exit_code), reiniciando en 3s..." | tee -a "$log_file"
    sleep 3
done
EOF

echo "[6/6] Creando script del bot..."
cat > bot_server.sh << 'EOF'
#!/bin/bash

ECONOMY_FILE="economy_data.json"

cd "$(dirname "$0")"

initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "Archivo de economía creado."
    fi
}

add_player_if_new() {
    local player_name="$1"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_exists=$(echo "$current_data" | jq --arg player "$player_name" '.players | has($player)')
    
    if [ "$player_exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_help_time": 0}')
        echo "$current_data" > "$ECONOMY_FILE"
        echo "Jugador añadido: $player_name"
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
    echo "Bono de bienvenida para $player_name"
    send_server_command "say ¡Bienvenido $player_name! Recibiste 1 ticket de regalo. Escribe !economy_help para más información."
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
        echo "Ticket de login para $player_name (Total: $new_tickets)"
        send_server_command "say $player_name, ¡recibiste 1 ticket por conectarte! Ahora tienes $new_tickets tickets."
    else
        local next_login=$((last_login + 3600))
        local time_left=$((next_login - current_time))
        echo "$player_name debe esperar $((time_left / 60)) minutos para el próximo ticket"
    fi
}

show_help_if_needed() {
    local player_name="$1"
    local current_time=$(date +%s)
    local current_data=$(cat "$ECONOMY_FILE")
    local last_help_time=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].last_help_time')
    
    if [ "$last_help_time" -eq 0 ] || [ $((current_time - last_help_time)) -ge 300 ]; then
        send_server_command "say $player_name, escribe !economy_help para ver comandos de economía."
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson time "$current_time" '.players[$player].last_help_time = $time')
        echo "$current_data" > "$ECONOMY_FILE"
    fi
}

send_server_command() {
    local command="$1"
    
    if [ -p "server_pipe" ]; then
        echo "$command" > server_pipe &
        echo "Comando enviado: $command"
    else
        echo "Advertencia: No se pudo enviar comando. Named pipe no encontrado."
        echo "Comando: $command"
    fi
}

process_message() {
    local player_name="$1"
    local message="$2"
    local current_data=$(cat "$ECONOMY_FILE")
    local player_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
    
    case "$message" in
        "hi"|"hello"|"Hi"|"Hello"|"hey"|"Hey")
            send_server_command "say ¡Bienvenido al servidor, $player_name! Escribe !tickets para ver tus tickets."
            ;;
        "!tickets")
            send_server_command "say $player_name, tienes $player_tickets tickets."
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
                send_server_command "say $player_name ha sido promovido a MOD por 10 tickets! Tickets restantes: $new_tickets"
            else
                send_server_command "say $player_name, necesitas $((10 - player_tickets)) tickets más para comprar MOD."
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
                send_server_command "say $player_name ha sido promovido a ADMIN por 20 tickets! Tickets restantes: $new_tickets"
            else
                send_server_command "say $player_name, necesitas $((20 - player_tickets)) tickets más para comprar ADMIN."
            fi
            ;;
        "!economy_help")
            send_server_command "say Comandos de economía: !tickets (ver tickets), !buy_mod (10 tickets para MOD), !buy_admin (20 tickets para ADMIN)"
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
            echo "Jugador $player_name no encontrado."
            return
        fi
        
        local current_tickets=$(echo "$current_data" | jq -r --arg player "$player_name" '.players[$player].tickets')
        local new_tickets=$((current_tickets + tickets_to_add))
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --argjson tickets "$new_tickets" \
            '.players[$player].tickets = $tickets')
        
        current_data=$(echo "$current_data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" --argjson amount "$tickets_to_add" \
            '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        
        echo "$current_data" > "$ECONOMY_FILE"
        echo "$tickets_to_add tickets añadidos a $player_name (Total: $new_tickets)"
        send_server_command "say $player_name recibió $tickets_to_add tickets del admin! Total: $new_tickets"
    else
        echo "Comando admin desconocido: $command"
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
    echo "     Bot de Economía The Blockheads"
    echo "========================================"
    echo "Monitoreando: $log_file"
    echo "Comandos: !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "Comandos admin: !send_ticket <jugador> <cantidad>"
    echo "========================================"
    echo "Para enviar comandos admin, escríbelos abajo:"
    
    if [ ! -p "server_pipe" ]; then
        mkfifo "server_pipe"
        echo "Named pipe creado para comunicación"
    fi
    
    while read -r admin_command; do
        if [[ "$admin_command" == "!send_ticket "* ]]; then
            process_admin_command "$admin_command"
        elif [[ "$admin_command" == "quit" ]]; then
            echo "Deteniendo bot..."
            exit 0
        else
            echo "Comando desconocido. Usa: !send_ticket <jugador> <cantidad>"
        fi
    done &
    
    tail -n 0 -F "$log_file" | filter_server_log | while read line; do
        if [[ "$line" =~ ([a-zA-Z0-9_]+)\ connected\.$ ]]; then
            local player_name="${BASH_REMATCH[1]}"
            echo "Jugador conectado: $player_name"
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
            echo "Comando admin desde consola: $admin_command"
            process_admin_command "$admin_command"
            continue
        fi
    done
}

if [ $# -eq 1 ]; then
    initialize_economy
    monitor_log "$1"
else
    echo "Uso: $0 <archivo_log_servidor>"
    echo "Proporciona la ruta al archivo de log del servidor"
    echo "Ejemplo: ./bot_server.sh ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log"
    exit 1
fi
EOF

chown "$ORIGINAL_USER:$ORIGINAL_USER" start.sh "$SERVER_BINARY" bot_server.sh
chmod 755 start.sh "$SERVER_BINARY" bot_server.sh

sudo -u "$ORIGINAL_USER" bash -c 'echo "{\"players\": {}, \"transactions\": []}" > economy_data.json'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json

rm -f "$TEMP_FILE"

echo "================================================================"
echo "¡Instalación completada correctamente!"
echo "================================================================"
echo "Para ver comandos del servidor: ./blockheads_server171 --help"
echo ""
echo "Para iniciar el servidor:"
echo "  ./start.sh"
echo ""
echo "Para iniciar el bot de economía:"
echo "  ./bot_server.sh ~/GNUstep/Library/Application Support/TheBlockheads/saves/83cad395edb8d0f1912fec89508d8a1d/console.log"
echo ""
echo "Para detener todo:"
echo "  pkill -f blockheads_server171"
echo "================================================================"
echo "Características del Sistema de Economía:"
echo "  - Jugadores nuevos reciben 1 ticket inmediatamente"
echo "  - Jugadores reciben 1 ticket cada hora al conectarse"
echo "  - Comandos: !tickets, !buy_mod (10), !buy_admin (20)"
echo "  - Comandos admin: !send_ticket <jugador> <cantidad>"
echo "================================================================"
echo "Verificando ejecutable..."
if sudo -u "$ORIGINAL_USER" ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Estado: Ejecutable verificado correctamente"
else
    echo "Advertencia: El ejecutable podría tener problemas de compatibilidad"
fi
echo "================================================================"
