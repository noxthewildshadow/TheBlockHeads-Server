#!/bin/bash
set -euo pipefail

# Setup.sh para TheBlockheads server — Instalador completo y corregido
# Diseñado para ejecutarse con:
# curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/Setup.sh | sudo bash

# Comprobar permisos root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Este instalador debe ejecutarse con privilegios root."
  echo "Usa: curl ... | sudo bash"
  exit 1
fi

# Usuario original que ejecutó sudo
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
  USER_HOME="/home/$ORIGINAL_USER"
fi

# Variables de configuración
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
INSTALL_DIR="$USER_HOME/blockheads_server"
TMP_DOWNLOAD="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY_NAME="blockheads_server171"

echo "================================================================"
echo "The Blockheads Linux Server - Instalador corregido"
echo "Instalando en: $INSTALL_DIR"
echo "Usuario propietario: $ORIGINAL_USER"
echo "================================================================"

# 1) Instalar dependencias del sistema (intentar instalar paquetes útiles)
echo "[1/5] Instalando paquetes necesarios..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true

# Paquetes mínimos que usaremos. Si alguno no existe, sigue adelante.
apt-get install -y wget jq screen lsof patchelf coreutils util-linux software-properties-common >/dev/null 2>&1 || true
# Intentamos paquetes opcionales que el binario pudiera necesitar (no fallamos si no están)
apt-get install -y libgnustep-base1.28 libdispatch0 >/dev/null 2>&1 || true

echo "[2/5] Preparando directorio de instalación..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
chown "$ORIGINAL_USER:$ORIGINAL_USER" "$INSTALL_DIR"

# 2) Descargar y extraer servidor
echo "[3/5] Descargando servidor..."
if ! wget -q "$SERVER_URL" -O "$TMP_DOWNLOAD"; then
  echo "ERROR: No se pudo descargar el archivo del servidor desde: $SERVER_URL"
  echo "Verifica tu conexión o la URL."
  exit 1
fi

echo "[4/5] Extrayendo archivos..."
EXTRACT_DIR="/tmp/blockheads_extract_$$"
mkdir -p "$EXTRACT_DIR"
if ! tar xzf "$TMP_DOWNLOAD" -C "$EXTRACT_DIR"; then
  echo "ERROR: Falla al extraer el archivo. El archivo puede estar corrupto."
  rm -rf "$EXTRACT_DIR" "$TMP_DOWNLOAD"
  exit 1
fi

# Mover contenido extraído a INSTALL_DIR
cp -r "$EXTRACT_DIR"/* "$INSTALL_DIR"/ 2>/dev/null || true
rm -rf "$EXTRACT_DIR"
rm -f "$TMP_DOWNLOAD"

# Buscar binario dentro de INSTALL_DIR y renombrar si es necesario
cd "$INSTALL_DIR" || exit 1
if [ ! -f "$SERVER_BINARY_NAME" ]; then
  ALTERNATIVE_BINARY=$(find . -maxdepth 2 -type f -executable -name "*blockheads*" | head -n 1 || true)
  if [ -n "$ALTERNATIVE_BINARY" ]; then
    echo "Encontrado binario alternativo: $ALTERNATIVE_BINARY"
    mv "$ALTERNATIVE_BINARY" "./$SERVER_BINARY_NAME" || true
  fi
fi

if [ ! -f "./$SERVER_BINARY_NAME" ]; then
  echo "WARNING: No se encontró el binario $SERVER_BINARY_NAME en el paquete."
  echo "Contenido del directorio de instalación:"
  ls -la "$INSTALL_DIR"
  # seguimos para crear scripts aunque falte binario (usuario puede añadirlo manualmente)
fi

chmod +x "./$SERVER_BINARY_NAME" 2>/dev/null || true

# 3) Crear scripts corregidos en INSTALL_DIR
echo "[5/5] Creando scripts start_server.sh, bot_server.sh y stop_server.sh..."

# start_server.sh
cat > "$INSTALL_DIR/start_server.sh" <<'EOF'
#!/bin/bash
set -e

SERVER_BINARY="./blockheads_server171"
DEFAULT_PORT=12153
SCREEN_SERVER="blockheads_server"
SCREEN_BOT="blockheads_bot"

show_usage() {
    echo "Uso: $0 start [WORLD_ID] [PORT]"
    echo "  start WORLD_ID PORT - Inicia el servidor y el bot"
    echo "  stop                - Detiene servidor y bot"
    echo "  status              - Muestra estado"
    echo ""
    echo "Nota: Primero crea un mundo con: ./blockheads_server171 -n"
}

is_port_in_use() {
    local port="$1"
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null ; then
        return 0
    else
        return 1
    fi
}

free_port() {
    local port="$1"
    echo "Intentando liberar el puerto $port..."
    local pids
    pids=$(lsof -ti ":$port" || true)
    if [ -n "$pids" ]; then
        echo "Matando procesos: $pids"
        kill -9 $pids 2>/dev/null || true
        sleep 1
    fi
    pkill -f "./blockheads_server171" 2>/dev/null || true
    if is_port_in_use "$port"; then
        echo "ERROR: No se pudo liberar el puerto $port"
        return 1
    fi
    return 0
}

check_world_exists() {
    local world_id="$1"
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"
    if [ ! -d "$world_dir" ]; then
        echo "Error: El mundo '$world_id' no existe."
        echo "Crea un mundo con: ./blockheads_server171 -n"
        return 1
    fi
    return 0
}

start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"

    if is_port_in_use "$port"; then
        echo "Puerto $port en uso, intentando liberar..."
        if ! free_port "$port"; then
            echo "No se puede iniciar servidor."
            return 1
        fi
    fi

    killall screen 2>/dev/null || true
    sleep 1

    if ! check_world_exists "$world_id"; then
        return 1
    fi

    local log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
    local log_file="$log_dir/console.log"
    mkdir -p "$log_dir"

    echo "$world_id" > world_id.txt

    screen -dmS "$SCREEN_SERVER" bash -c "
        restart_count=0
        max_restarts=3
        while [ \$restart_count -lt \$max_restarts ]; do
            echo \"Iniciando servidor (reinicio #\$((++restart_count)))\"
            if $SERVER_BINARY -o '$world_id' -p $port 2>&1 | tee -a '$log_file'; then
                echo 'Servidor cerrado normalmente.'
                break
            else
                exit_code=\$?
                echo 'Servidor falló con código:' \$exit_code
                if tail -n 5 '$log_file' | grep -q \"port.*already in use\"; then
                    echo 'ERROR: Puerto ya en uso. No se reintentará.'
                    break
                fi
                sleep 3
            fi
        done
    "

    echo "Esperando log..."
    local wait_time=0
    while [ ! -f "$log_file" ] && [ $wait_time -lt 10 ]; do
        sleep 1
        ((wait_time++))
    done

    if [ ! -f "$log_file" ]; then
        echo "ERROR: No se creó el archivo de log."
        return 1
    fi

    start_bot "$log_file"

    echo "Servidor iniciado."
    echo "screen -r $SCREEN_SERVER (consola)"
    echo "screen -r $SCREEN_BOT (bot)"
}

start_bot() {
    local log_file="$1"
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot ya en ejecución."
        return 0
    fi
    sleep 5
    screen -dmS "$SCREEN_BOT" bash -c "
        ./bot_server.sh '$log_file'
    "
    echo "Bot iniciado."
}

stop_server() {
    screen -S "$SCREEN_SERVER" -X quit 2>/dev/null || true
    screen -S "$SCREEN_BOT" -X quit 2>/dev/null || true
    pkill -f "./blockheads_server171" 2>/dev/null || true
    pkill -f "tail -n 0 -F" 2>/dev/null || true
    killall screen 2>/dev/null || true
}

show_status() {
    echo "=== ESTADO ==="
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
    if [ -f "world_id.txt" ]; then
        echo "Mundo: $(cat world_id.txt)"
    fi
    echo "============="
}

case "$1" in
    start)
        if [ -z "${2:-}" ]; then
            echo "Debes indicar WORLD_ID"
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
    *)
        show_usage
        ;;
esac
EOF

# bot_server.sh (corregido: mkfifo fallback, sin caracteres raros, jq arreglado)
cat > "$INSTALL_DIR/bot_server.sh" <<'EOF'
#!/bin/bash
set -e

SCAN_INTERVAL=5
LOG_FILE=""
WORLD_DIR=""
ECONOMY_FILE=""

initialize_economy() {
    local world_dir="$1"
    ECONOMY_FILE="$world_dir/economy_data.json"
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "Economy file creado: $ECONOMY_FILE"
    fi
}

is_player_in_list() {
    local player_name="$1"
    local list_type="$2"
    local file="$WORLD_DIR/${list_type}list.txt"
    local lp
    lp=$(echo "$player_name" | tr '[:upper:]' '[:lower:]')
    if [ -f "$file" ]; then
        if grep -q "^$lp$" "$file"; then
            return 0
        fi
    fi
    return 1
}

add_player_if_new() {
    local player_name="$1"
    local data
    data=$(cat "$ECONOMY_FILE")
    local exists
    exists=$(echo "$data" | jq --arg player "$player_name" '.players | has($player)')
    if [ "$exists" = "false" ]; then
        data=$(echo "$data" | jq --arg player "$player_name" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0, "purchases": []}')
        echo "$data" > "$ECONOMY_FILE"
        give_first_time_bonus "$player_name"
        return 0
    fi
    return 1
}

give_first_time_bonus() {
    local player_name="$1"
    local data
    data=$(cat "$ECONOMY_FILE")
    local now
    now=$(date +%s)
    data=$(echo "$data" | jq --arg player "$player_name" '.players[$player].tickets = 1')
    data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_login = $time')
    data=$(echo "$data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "welcome_bonus", "tickets": 1, "time": $time}]')
    echo "$data" > "$ECONOMY_FILE"
}

grant_login_ticket() {
    local player_name="$1"
    local now
    now=$(date +%s)
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_login
    last_login=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].last_login // 0')
    if [ "$last_login" -eq 0 ] || [ $((now - last_login)) -ge 3600 ]; then
        local tickets
        tickets=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].tickets // 0')
        local new_t=$((tickets + 1))
        data=$(echo "$data" | jq --arg player "$player_name" --argjson tickets "$new_t" '.players[$player].tickets = $tickets')
        data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_login = $time')
        data=$(echo "$data" | jq --arg player "$player_name" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "login_bonus", "tickets": 1, "time": $time}]')
        echo "$data" > "$ECONOMY_FILE"
        send_server_command "$player_name, you received 1 login ticket! You now have $new_t tickets."
    fi
}

show_welcome_message() {
    local player_name="$1"
    local is_new="$2"
    local now
    now=$(date +%s)
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_w
    last_w=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].last_welcome_time // 0')
    if [ "$last_w" -eq 0 ] || [ $((now - last_w)) -ge 180 ]; then
        if [ "$is_new" = "true" ]; then
            send_server_command "Hello $player_name! Welcome to the server. Type !tickets to check your ticket balance."
        else
            send_server_command "Welcome back $player_name! Type !economy_help to see economy commands."
        fi
        data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_welcome_time = $time')
        echo "$data" > "$ECONOMY_FILE"
    fi
}

show_help_if_needed() {
    local player_name="$1"
    local now
    now=$(date +%s)
    local data
    data=$(cat "$ECONOMY_FILE")
    local last_help
    last_help=$(echo "$data" | jq -r --arg player "$player_name" '.players[$player].last_help_time // 0')
    if [ "$last_help" -eq 0 ] || [ $((now - last_help)) -ge 300 ]; then
        send_server_command "$player_name, type !economy_help to see economy commands."
        data=$(echo "$data" | jq --arg player "$player_name" --argjson time "$now" '.players[$player].last_help_time = $time')
        echo "$data" > "$ECONOMY_FILE"
    fi
}

send_server_command() {
    local msg="$1"
    if screen -S blockheads_server -X stuff "$msg$(printf \\r)" 2>/dev/null; then
        echo "Sent: $msg"
    else
        echo "Could not send to server (is it running?)"
    fi
}

has_purchased() {
    local player="$1"
    local item="$2"
    local data
    data=$(cat "$ECONOMY_FILE")
    local res
    res=$(echo "$data" | jq --arg player "$player" --arg item "$item" '.players[$player].purchases | index($item) != null')
    if [ "$res" = "true" ]; then
        return 0
    fi
    return 1
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
    local data
    data=$(cat "$ECONOMY_FILE")
    local tickets
    tickets=$(echo "$data" | jq -r --arg player "$player" '.players[$player].tickets // 0')

    case "$message" in
        "hi"|"hello"|"hola"|"Hola")
            send_server_command "Hello $player! Type !tickets."
            ;;
        "!tickets")
            send_server_command "$player, you have $tickets tickets."
            ;;
        "!buy_mod")
            if has_purchased "$player" "mod" || is_player_in_list "$player" "mod"; then
                send_server_command "$player, you already have MOD."
            elif [ "$tickets" -ge 10 ]; then
                local new_t=$((tickets - 10))
                data=$(echo "$data" | jq --arg player "$player" --argjson tickets "$new_t" '.players[$player].tickets = $tickets')
                data=$(echo "$data" | jq --arg player "$player" '.players[$player].purchases += ["mod"]')
                data=$(echo "$data" | jq --arg player "$player" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                echo "$data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/mod $player$(printf \\r)"
                send_server_command "Congratulations $player! You are now MOD. Remaining: $new_t"
            else
                send_server_command "$player, need $((10 - tickets)) more tickets to buy MOD."
            fi
            ;;
        "!buy_admin")
            if has_purchased "$player" "admin" || is_player_in_list "$player" "admin"; then
                send_server_command "$player, you already have ADMIN."
            elif [ "$tickets" -ge 20 ]; then
                local new_t=$((tickets - 20))
                data=$(echo "$data" | jq --arg player "$player" --argjson tickets "$new_t" '.players[$player].tickets = $tickets')
                data=$(echo "$data" | jq --arg player "$player" '.players[$player].purchases += ["admin"]')
                data=$(echo "$data" | jq --arg player "$player" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "purchase", "item": "admin", "tickets": -20, "time": $time}]')
                echo "$data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/admin $player$(printf \\r)"
                send_server_command "Congratulations $player! You are now ADMIN. Remaining: $new_t"
            else
                send_server_command "$player, need $((20 - tickets)) more tickets to buy ADMIN."
            fi
            ;;
        "!economy_help")
            send_server_command "Commands: !tickets, !buy_mod (10), !buy_admin (20)"
            ;;
    esac
}

process_admin_command() {
    local cmd="$1"
    local data
    data=$(cat "$ECONOMY_FILE")

    if [[ "$cmd" =~ ^!send_ticket\ ([a-zA-Z0-9_]+)\ ([0-9]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        local n="${BASH_REMATCH[2]}"
        local exists
        exists=$(echo "$data" | jq --arg player "$p" '.players | has($player)')
        if [ "$exists" = "false" ]; then
            echo "Player $p not found."
            return
        fi
        local cur
        cur=$(echo "$data" | jq -r --arg player "$p" '.players[$player].tickets // 0')
        local new=$((cur + n))
        data=$(echo "$data" | jq --arg player "$p" --argjson tickets "$new" '.players[$player].tickets = $tickets')
        data=$(echo "$data" | jq --arg player "$p" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" --argjson amount "$n" '.transactions += [{"player": $player, "type": "admin_gift", "tickets": $amount, "time": $time}]')
        echo "$data" > "$ECONOMY_FILE"
        send_server_command "$p received $n tickets from admin! Total: $new"
    elif [[ "$cmd" =~ ^!make_mod\ ([a-zA-Z0-9_]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/mod $p$(printf \\r)"
        send_server_command "$p has been promoted to MOD by admin!"
    elif [[ "$cmd" =~ ^!make_admin\ ([a-zA-Z0-9_]+)$ ]]; then
        local p="${BASH_REMATCH[1]}"
        screen -S blockheads_server -X stuff "/admin $p$(printf \\r)"
        send_server_command "$p has been promoted to ADMIN by admin!"
    else
        echo "Unknown admin command: $cmd"
    fi
}

filter_server_log() {
    while read -r line; do
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]]; then
            continue
        fi
        if [[ "$line" == *"SERVER: say"* ]] || [[ "$line" == *"received"* && "$line" == *"ticket"* ]]; then
            continue
        fi
        echo "$line"
    done
}

monitor_log() {
    local log="$1"
    LOG_FILE="$log"
    WORLD_DIR=$(dirname "$LOG_FILE")
    initialize_economy "$WORLD_DIR"

    echo "Monitoring: $LOG_FILE"
    echo "Admin pipe: /tmp/blockheads_admin_pipe"

    local admin_pipe="/tmp/blockheads_admin_pipe"
    rm -f "$admin_pipe" 2>/dev/null || true
    local use_fifo=0
    if command -v mkfifo >/dev/null 2>&1; then
        if mkfifo "$admin_pipe" 2>/dev/null; then
            use_fifo=1
        else
            touch "$admin_pipe"
            use_fifo=0
        fi
    else
        touch "$admin_pipe"
        use_fifo=0
    fi

    if [ "$use_fifo" -eq 1 ]; then
        ( while true; do
            if read -r admin_cmd < "$admin_pipe"; then
                process_admin_command "$admin_cmd"
            fi
        done ) &
    else
        ( tail -n 0 -F "$admin_pipe" 2>/dev/null | while read -r admin_cmd; do
            if [ -n "$admin_cmd" ]; then
                process_admin_command "$admin_cmd"
            fi
        done ) &
    fi

    ( while read -r admin_cmd; do
        echo "$admin_cmd" >> "$admin_pipe"
    done ) &

    declare -A welcome_shown

    tail -n 0 -F "$LOG_FILE" 2>/dev/null | filter_server_log | while read -r line; do
        if [[ "$line" =~ Player\ Connected\ ([a-zA-Z0-9_]+)\ \| ]]; then
            local p="${BASH_REMATCH[1]}"
            if [[ "$p" == "SERVER" ]]; then continue; fi
            local is_new="false"
            if add_player_if_new "$p"; then is_new="true"; fi
            if [ "$is_new" = "true" ]; then
                welcome_shown["$p"]=1
            else
                if [ -z "${welcome_shown[$p]}" ]; then
                    show_welcome_message "$p" "false"
                    welcome_shown["$p"]=1
                fi
                grant_login_ticket "$p"
            fi
            continue
        fi

        if [[ "$line" =~ Player\ Disconnected\ ([a-zA-Z0-9_]+) ]]; then
            local p="${BASH_REMATCH[1]}"
            unset welcome_shown["$p"]
            continue
        fi

        if [[ "$line" =~ ^([a-zA-Z0-9_]+):\ (.+)$ ]]; then
            local p="${BASH_REMATCH[1]}"
            local msg="${BASH_REMATCH[2]}"
            if [[ "$p" == "SERVER" ]]; then continue; fi
            add_player_if_new "$p"
            process_message "$p" "$msg"
            continue
        fi
    done

    wait
    rm -f "$admin_pipe" 2>/dev/null || true
}

if [ $# -eq 1 ]; then
    monitor_log "$1"
else
    echo "Usage: $0 <server_log_file>"
    exit 1
fi
EOF

# stop_server.sh
cat > "$INSTALL_DIR/stop_server.sh" <<'EOF'
#!/bin/bash
set -e
echo "Stopping Blockheads server and cleaning up..."
screen -S blockheads_server -X quit 2>/dev/null || true
screen -S blockheads_bot -X quit 2>/dev/null || true
pkill -f "./blockheads_server171" 2>/dev/null || true
pkill -f "tail -n 0 -F" 2>/dev/null || true
rm -f /tmp/blockheads_admin_pipe 2>/dev/null || true
killall screen 2>/dev/null || true
echo "Stopped."
screen -ls || true
EOF

# 4) Ajustes de permisos y propiedad
chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/start_server.sh" "$INSTALL_DIR/bot_server.sh" "$INSTALL_DIR/stop_server.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/$SERVER_BINARY_NAME" 2>/dev/null || true

echo "================================================================"
echo "Instalación completada en: $INSTALL_DIR"
echo ""
cat <<EOF
Siguientes pasos (como usuario $ORIGINAL_USER):

1) Conéctate al directorio:
   cd $INSTALL_DIR

2) (Opcional) Crea un mundo por primera vez:
   ./blockheads_server171 -n

3) Inicia el servidor + bot:
   ./start_server.sh start YOUR_WORLD_ID 12153

4) Ver la consola del servidor:
   screen -r blockheads_server

5) Ver la consola del bot:
   screen -r blockheads_bot

Admin commands:
 - Desde otra terminal (mientras el bot corre):
   echo "!send_ticket playername 5" >> /tmp/blockheads_admin_pipe
   echo "!make_mod playername" >> /tmp/blockheads_admin_pipe

Notas:
 - Si mkfifo no está disponible, el bot usa un archivo regular en /tmp/blockheads_admin_pipe (fallback).
 - Los datos de economía se guardan por mundo en: .../saves/WORLD_ID/economy_data.json
 - Si el binario no se incluye en el paquete descargado, copia manualmente tu binario como $INSTALL_DIR/$SERVER_BINARY_NAME
EOF
echo "================================================================"

exit 0
