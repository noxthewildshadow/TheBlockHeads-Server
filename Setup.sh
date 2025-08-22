#!/bin/bash
set -euo pipefail

# =====================================================
# Setup.sh - Instalador completo para The Blockheads server
# Diseñado para ejecutarse con:
#   curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/Setup.sh | sudo bash
# =====================================================

STEP=0
total_steps=6
run_step() {
    STEP=$((STEP+1))
    local desc="$1"
    echo ""
    echo "=== Paso ${STEP}/${total_steps}: ${desc} ==="
}

fail_exit() {
    echo "[ERROR] $1"
    exit 1
}

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)."
    echo "Ejemplo: curl -sSL <url> | sudo bash"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6 || echo "/home/$ORIGINAL_USER")

# Configuración
# URL del bundle (fallback a web.archive)
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "===================================================="
echo " The Blockheads - Instalador automatizado"
echo " Instalando para usuario: $ORIGINAL_USER (home: $USER_HOME)"
echo "===================================================="

# -----------------------
# Paso 1: Instalar dependencias (silencioso, con fallback a mostrar salida)
# -----------------------
run_step "Instalando dependencias (apt-get). Esto puede tardar..."
{
    apt-get update -y >/dev/null 2>&1
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen psmisc >/dev/null 2>&1
} || {
    echo "[WARN] La instalación silenciosa falló. Reintentando mostrando salida..."
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen psmisc || fail_exit "No se pudieron instalar dependencias. Ejecuta 'apt-get install' manualmente."
}
echo "[OK] Dependencias procesadas."

# -----------------------
# Paso 2: Descargar bundle del servidor (silencioso)
# -----------------------
run_step "Descargando paquete del servidor (silencioso)..."
rm -f "$TEMP_FILE"
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "[ERROR] No se pudo descargar el paquete desde: $SERVER_URL"
    echo "Intentando descargar mostrando error..."
    wget "$SERVER_URL" -O "$TEMP_FILE" || fail_exit "Descarga fallida. Revisa conexión o URL."
fi
echo "[OK] Descarga completada."

# -----------------------
# Paso 3: Extraer archivos (silencioso)
# -----------------------
run_step "Extrayendo archivos..."
if ! tar xzf "$TEMP_FILE" -C . >/dev/null 2>&1; then
    echo "[WARN] Extracción silenciosa falló. Listando contenido del tar para diagnóstico:"
    tar -tzf "$TEMP_FILE" || true
    fail_exit "Error al extraer el paquete. Archive corrupto o incompatibilidad."
fi
echo "[OK] Extracción completada."

# -----------------------
# Paso 4: Localizar binario y aplicar permisos
# -----------------------
run_step "Preparando binario del servidor y permisos..."
if [ ! -f "./$SERVER_BINARY" ]; then
    ALTERNATIVE=$(find . -maxdepth 3 -type f -executable -iname "*blockheads*" | head -n1 || true)
    if [ -n "$ALTERNATIVE" ]; then
        mv "$ALTERNATIVE" "./$SERVER_BINARY"
        echo "[INFO] Movido ejecutable encontrado: $ALTERNATIVE -> ./$SERVER_BINARY"
    else
        fail_exit "No se encontró el binario '$SERVER_BINARY' en el paquete extraído."
    fi
fi
chmod +x "./$SERVER_BINARY" || fail_exit "No se pudo hacer ejecutable: ./$SERVER_BINARY"
echo "[OK] Binario listo: ./$SERVER_BINARY"

# -----------------------
# Paso 5: Patchelf (compatibilidad) - mejor esfuerzo (silencioso)
# -----------------------
run_step "Aplicando parches de compatibilidad (patchelf - mejor esfuerzo)..."
{
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libffi.so.6 libffi.so.8 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 "./$SERVER_BINARY" 2>/dev/null || true
    patchelf --replace-needed libdispatch.so libdispatch.so.0 "./$SERVER_BINARY" 2>/dev/null || true
} || true
echo "[OK] Parches intentados (warnings no fatales)."

# -----------------------
# Paso 6: Crear scripts auxiliares (start, bot, stop, create_world)
# -----------------------
run_step "Creando scripts auxiliares: start_server.sh, bot_server.sh, stop_server.sh, create_world.sh ..."

# START SERVER
cat > start_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SERVER_BINARY="./blockheads_server171"
DEFAULT_PORT=12153
SCREEN_SERVER="blockheads_server"
SCREEN_BOT="blockheads_bot"

show_usage() {
    cat <<EOM
Uso:
  $0 start WORLD_ID [PORT]   - Inicia servidor y bot para el world
  $0 stop                    - Para servidor y bot (sesiones screen)
  $0 status                  - Muestra estado
  $0 create_world            - Crea un mundo nuevo y muestra SOLO el World ID

Ejemplo:
  $0 start c1ce8d817c47daa51356cdd4ab64f032 12153

Nota: Para crear un mundo desde el binario sin mucha salida:
  ./create_world.sh
EOM
}

check_world_exists() {
    local world_id="$1"
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"
    if [ ! -d "$world_dir" ]; then
        echo "Error: World '$world_id' no encontrado en: $world_dir"
        return 1
    fi
    return 0
}

cleanup_named_sessions() {
    screen -S "$SCREEN_BOT" -X quit 2>/dev/null || true
    screen -S "$SCREEN_SERVER" -X quit 2>/dev/null || true
    pkill -f "$SERVER_BINARY" 2>/dev/null || true
    pkill -f "tail -n 0 -F" 2>/dev/null || true
}

start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"

    echo "[start] Limpiando sesiones previas..."
    cleanup_named_sessions

    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "[start] El servidor ya parece estar corriendo (screen detectado). Para forzar restart: $0 stop && $0 start $world_id $port"
        return 0
    fi

    if ! check_world_exists "$world_id"; then
        return 1
    fi

    local log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
    mkdir -p "$log_dir"
    local log_file="$log_dir/console.log"

    echo "[start] Iniciando servidor para world: $world_id en puerto $port"
    echo "$world_id" > world_id.txt

    # Intento liberar puerto (mejor esfuerzo)
    if command -v fuser >/dev/null 2>&1; then
        fuser -k "${port}/tcp" 2>/dev/null || true
    else
        if ss -ltnp 2>/dev/null | grep -q ":${port} "; then
            echo "[start] Puerto $port parece ocupado, matando procesos asociados (mejor esfuerzo)."
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

    echo "[start] Esperando creación de archivo de log (timeout 30s)..."
    local waited=0
    local maxwait=30
    while [ ! -f "$log_file" ] && [ $waited -lt $maxwait ]; do
        sleep 1
        waited=$((waited+1))
    done

    if [ ! -f "$log_file" ]; then
        echo "[warn] El log no apareció en $maxwait s. Revisa permisos o salida del binario."
    else
        echo "[OK] Log creado: $log_file"
    fi

    start_bot "$log_file"

    echo "[start] Servidor y bot iniciados. Para adjuntarte al console: screen -r $SCREEN_SERVER"
}

start_bot() {
    local log_file="$1"
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "[bot] El bot ya se encuentra corriendo."
        return 0
    fi
    sleep 5
    screen -dmS "$SCREEN_BOT" bash -c "
echo '[bot] Iniciando bot - monitor: $log_file'
./bot_server.sh '$log_file'
"
    echo "[bot] Bot iniciado en la sesión screen: $SCREEN_BOT"
}

stop_server() {
    echo "[stop] Parando servidor y bot..."
    cleanup_named_sessions
    echo "[stop] Hecho. Revisa sesiones con: screen -ls"
}

show_status() {
    echo "=== ESTADO THE BLOCKHEADS ==="
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Servidor: RUNNING (screen: $SCREEN_SERVER)"
    else
        echo "Servidor: STOPPED"
    fi
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot: RUNNING (screen: $SCREEN_BOT)"
    else
        echo "Bot: STOPPED"
    fi
    if [ -f world_id.txt ]; then
        echo "World actual: $(cat world_id.txt)"
    fi
    echo "============================="
}

case "${1:-help}" in
    start)
        if [ -z "${2:-}" ]; then
            echo "Error: WORLD_ID requerido."
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
    create_world)
        ./create_world.sh
        ;;
    help|*)
        show_usage
        ;;
esac
EOF

# BOT SERVER (mejorado: evita duplicados y el "welcome b!" extraño)
cat > bot_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# bot_server.sh (mejorado)
ECONOMY_FILE="economy_data.json"
LOG_FILE="${1:-}"

if [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <server_log_file>"
    exit 1
fi

send_server_raw() {
    local message="$1"
    screen -S blockheads_server -X stuff "$message$(printf \\r)" 2>/dev/null || {
        echo "[bot] no se pudo enviar raw (¿screen blockheads_server activo?)"
    }
}
send_server_chat() {
    local message="$1"
    screen -S blockheads_server -X stuff "say $message$(printf \\r)" 2>/dev/null || {
        echo "[bot] no se pudo enviar chat (¿screen blockheads_server activo?)"
    }
}
send_server_command() {
    local message="$1"
    if [[ "$message" =~ ^/ ]]; then
        send_server_raw "$message"
        return
    fi
    # Por defecto usamos raw para bienvenidas y respuestas
    send_server_raw "$message"
}

player_key() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

initialize_economy() {
    if [ ! -f "$ECONOMY_FILE" ]; then
        echo '{"players": {}, "transactions": []}' > "$ECONOMY_FILE"
        echo "[bot] economy file creado: $ECONOMY_FILE"
    fi
}

is_player_in_list() {
    local player_name="$1"; local list_type="$2"
    local world_dir; world_dir=$(dirname "$LOG_FILE")
    local list_file="$world_dir/${list_type}list.txt"
    local lower_name; lower_name=$(player_key "$player_name")
    [ -f "$list_file" ] && grep -q "^$lower_name$" "$list_file"
}

# add_player_if_new: solo actualiza datos (no envía bienvenida)
add_player_if_new() {
    local player_name="$1"
    local pkey; pkey=$(player_key "$player_name")
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local exists; exists=$(echo "$current_data" | jq --arg player "$pkey" '.players | has($player)')
    if [ "$exists" = "false" ]; then
        current_data=$(echo "$current_data" | jq --arg player "$pkey" '.players[$player] = {"tickets": 0, "last_login": 0, "last_welcome_time": 0, "last_help_time": 0, "purchases": []}')
        echo "$current_data" > "$ECONOMY_FILE"
        give_first_time_bonus_data "$pkey"
        return 0
    fi
    return 1
}

# Actualiza datos, no envía texto
give_first_time_bonus_data() {
    local pkey="$1"
    local current_data; current_data=$(cat "$ECONOMY_FILE")
    local now; now=$(date +%s)
    current_data=$(echo "$current_data" | jq --arg player "$pkey" '.players[$player].tickets = 1')
    current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson time "$now" '.players[$player].last_login = $time')
    current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "welcome_bonus", "tickets": 1, "time": $time}]')
    echo "$current_data" > "$ECONOMY_FILE"
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

    # Ignorar comandos sospechosos muy cortos como "!b"
    if [[ "${message}" =~ ^![a-zA-Z]{1,2}$ ]]; then
        echo "[bot] Ignorando mensaje corto/sospechoso: $message"
        return
    fi

    case "$message" in
        hi|hello|hola|Hola|Hi|Hello)
            send_server_command "Hello $player_name! Type !economy_help to see economy commands."
            ;;
        "!tickets")
            send_server_command "$player_name, you have $player_tickets tickets."
            ;;
        "!buy_mod")
            if has_purchased "$player_name" "mod" || is_player_in_list "$player_name" "mod"; then
                send_server_command "$player_name, you already have MOD rank."
            elif [ "$player_tickets" -ge 10 ]; then
                local new_tickets=$((player_tickets - 10))
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --argjson tickets "$new_tickets" '.players[$player].tickets = $tickets')
                add_purchase "$player_name" "mod"
                current_data=$(echo "$current_data" | jq --arg player "$pkey" --arg time "$(date '+%Y-%m-%d %H:%M:%S')" '.transactions += [{"player": $player, "type": "purchase", "item": "mod", "tickets": -10, "time": $time}]')
                echo "$current_data" > "$ECONOMY_FILE"
                screen -S blockheads_server -X stuff "/mod $player_name$(printf \\r)" 2>/dev/null || true
                send_server_command "Congratulations $player_name! You have been promoted to MOD for 10 tickets. Remaining tickets: $new_tickets"
            else
                send_server_command "$player_name, you need $((10 - player_tickets)) more tickets to buy MOD rank."
            fi
            ;;
        "!buy_admin")
            if has_purchased "$player_name" "admin" || is_player_in_list "$player_name" "admin"; then
                send_server_command "$player_name, you already have ADMIN rank."
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
            send_server_command "Economy commands: !tickets, !buy_mod (10), !buy_admin (20). Admins: !send_ticket <player> <amt>, !make_mod <player>, !make_admin <player>"
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
            echo "Player $player_name not found."
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
        if [[ "$line" == *"Server closed"* ]] || [[ "$line" == *"Starting server"* ]]; then
            continue
        fi
        echo "$line"
    done
}

monitor_log() {
    echo "[bot] Monitoring: $LOG_FILE"
    echo "[bot] Comandos disponibles (jugadores): !tickets, !buy_mod, !buy_admin, !economy_help"
    echo "[bot] Comandos admin (escribirlos en esta terminal): !send_ticket <player> <amount>, !make_mod <player>, !make_admin <player>"
    echo "================================================================"

    local admin_pipe="/tmp/blockheads_admin_pipe_$$"
    rm -f "$admin_pipe"; mkfifo "$admin_pipe"

    ( while read -r admin_command; do
          echo "$admin_command" > "$admin_pipe"
      done ) &

    ( while read -r admin_command < "$admin_pipe"; do
          process_admin_command "$admin_command"
      done ) &

    declare -A welcome_shown

    tail -n 0 -F "$LOG_FILE" | filter_server_log | while read -r line; do
        # Detección flexible de join
        if [[ "$line" =~ Player.*Connected.*([a-zA-Z0-9_]+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local pkey; pkey=$(player_key "$raw_name")
            echo "[bot] Player connected: $raw_name"
            local is_new="false"
            if add_player_if_new "$raw_name"; then
                is_new="true"
            fi
            # Solo una bienvenida por sesión para evitar duplicados
            if [ -z "${welcome_shown[$pkey]:-}" ]; then
                if [ "$is_new" = "true" ]; then
                    send_server_command "Welcome $raw_name! Type !economy_help to see economy commands."
                else
                    send_server_command "Welcome back $raw_name! Type !economy_help to see economy commands."
                    grant_login_ticket "$raw_name"
                fi
                welcome_shown[$pkey]=1
            fi
            continue
        fi

        # Disconnect -> limpiar flag
        if [[ "$line" =~ Player.*Disconnected.*([a-zA-Z0-9_]+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local pkey; pkey=$(player_key "$raw_name")
            unset welcome_shown[$pkey]
            echo "[bot] Player disconnected: $raw_name (welcome flag cleared)"
            continue
        fi

        # Chat detection: "<Player>: message"
        if [[ "$line" =~ ([a-zA-Z0-9_]+):[[:space:]](.+) ]]; then
            local raw_name="${BASH_REMATCH[1]}"
            local message="${BASH_REMATCH[2]}"
            # Ignorar mensajes extraños y muy cortos como "!b"
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

# CREATE_WORLD wrapper: corre ./blockheads_server171 -n y muestra SOLO el ID encontrado
cat > create_world.sh <<'EOF'
#!/bin/bash
set -euo pipefail
BIN="./blockheads_server171"
TMP="/tmp/create_world_output_$$.log"

if [ ! -x "$BIN" ]; then
    echo "Error: $BIN no encontrado o no ejecutable."
    exit 1
fi

# Ejecutar creación y capturar salida silenciosamente
"$BIN" -n > "$TMP" 2>&1 || true

# Buscar patrones comunes: UUID (36 chars) o 32 hex
WORLD_ID=$(grep -Eo '[0-9a-fA-F\-]{36}' "$TMP" | head -n1 || true)
if [ -z "$WORLD_ID" ]; then
    WORLD_ID=$(grep -Eo '[0-9a-fA-F]{32}' "$TMP" | head -n1 || true)
fi

if [ -n "$WORLD_ID" ]; then
    echo "$WORLD_ID"
    rm -f "$TMP"
    exit 0
else
    # Si no encontramos, mostramos la última línea por si el binario usa otro formato
    tail -n 10 "$TMP"
    rm -f "$TMP"
    exit 1
fi
EOF

# STOP SERVER
cat > stop_server.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "[stop] Parando sesiones named y limpiando..."
screen -S blockheads_server -X quit 2>/dev/null || true
screen -S blockheads_bot -X quit 2>/dev/null || true
pkill -f blockheads_server171 2>/dev/null || true
pkill -f "tail -n 0 -F" 2>/dev/null || true
echo "[stop] Hecho."
EOF

# Permisos y propiedad
chmod 755 start_server.sh bot_server.sh stop_server.sh create_world.sh "./$SERVER_BINARY"
chown "$ORIGINAL_USER:$ORIGINAL_USER" start_server.sh bot_server.sh stop_server.sh create_world.sh "./$SERVER_BINARY" || true

# Crear economy_data.json para el usuario no-root
run_step "Creando archivo economy_data.json para $ORIGINAL_USER..."
sudo -u "$ORIGINAL_USER" bash -c 'cat > economy_data.json <<JSON
{"players": {}, "transactions": []}
JSON'
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json || true
chmod 644 economy_data.json
echo "[OK] economy_data.json creado."

# Limpieza
rm -f "$TEMP_FILE" || true

echo ""
echo "===================================================="
echo " Instalación completada. Resumen rápido:"
echo " - Ejecutables y scripts creados en: $(pwd)"
echo " - Para crear un mundo y mostrar SOLO el ID: ./create_world.sh"
echo " - Para iniciar servidor y bot: ./start_server.sh start WORLD_ID [PORT]"
echo " - Para parar: ./start_server.sh stop  (o ./stop_server.sh)"
echo ""
echo "Comandos del bot (jugadores): !tickets, !buy_mod (10), !buy_admin (20), !economy_help"
echo "Comandos admin (escribir en la terminal del bot): !send_ticket <player> <amount>, !make_mod <player>, !make_admin <player>"
echo "===================================================="

# Verificación no fatal
if sudo -u "$ORIGINAL_USER" "./$SERVER_BINARY" --help >/dev/null 2>&1; then
    echo "[OK] El binario responde a --help."
else
    echo "[WARN] El binario puede necesitar dependencias adicionales en esta máquina."
fi

exit 0
