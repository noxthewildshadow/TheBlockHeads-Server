#!/bin/bash

# start_server.sh - start the server and the bot. Assumes working dir is the install directory.

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
}

# Verifica archivo binario
if [ ! -f "$SERVER_BINARY" ]; then
    echo "ERROR: $SERVER_BINARY no encontrado en el directorio actual."
    exit 1
fi

# Verificar puerto en uso
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
    local pids
    pids=$(lsof -ti ":$port")
    if [ -n "$pids" ]; then
        kill -9 $pids 2>/dev/null || true
        sleep 1
    fi
    killall screen 2>/dev/null || true
    is_port_in_use "$port" && return 1 || return 0
}

check_world_exists() {
    local world_id="$1"
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"
    if [ ! -d "$world_dir" ]; then
        echo "Error: El mundo '$world_id' no existe en $saves_dir"
        return 1
    fi
    return 0
}

start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"

    if is_port_in_use "$port"; then
        echo "Puerto $port en uso. Intentando liberar..."
        if ! free_port "$port"; then
            echo "No se pudo liberar el puerto $port"
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

    echo "Iniciando servidor con mundo: $world_id, puerto: $port"
    echo "$world_id" > world_id.txt

    screen -dmS "$SCREEN_SERVER" bash -c "
        while true; do
            echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando servidor...\"
            if $SERVER_BINARY -o '$world_id' -p $port 2>&1 | tee -a '$log_file'; then
                echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Servidor cerrado normalmente.\"
            else
                exit_code=\$?
                echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Servidor falló con código: \$exit_code\"
                if [ \$exit_code -eq 1 ] && tail -n 5 '$log_file' | grep -q \"port.*already in use\"; then
                    echo \"[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Puerto ya en uso. No se reintentará.\"
                    break
                fi
            fi
            echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Reiniciando en 5 segundos...\"
            sleep 5
        done
    "

    # Esperar log
    local wait_time=0
    while [ ! -f "$log_file" ] && [ $wait_time -lt 15 ]; do
        sleep 1
        ((wait_time++))
    done

    if [ ! -f "$log_file" ]; then
        echo "ERROR: no se creó $log_file; el servidor podría no haberse iniciado"
        return 1
    fi

    # Levantar bot
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot ya en ejecución"
    else
        screen -dmS "$SCREEN_BOT" bash -c "echo 'Iniciando bot...' && ./bot_server.sh '$log_file'"
        echo "Bot iniciado"
    fi

    echo "Servidor iniciado correctamente. Usa screen -r $SCREEN_SERVER para ver consola"
}

stop_server() {
    if screen -list | grep -q "$SCREEN_SERVER"; then
        screen -S "$SCREEN_SERVER" -X quit
        echo "Servidor detenido"
    else
        echo "Servidor no estaba en ejecución"
    fi

    if screen -list | grep -q "$SCREEN_BOT"; then
        screen -S "$SCREEN_BOT" -X quit
        echo "Bot detenido"
    else
        echo "Bot no estaba en ejecución"
    fi

    pkill -f "./$SERVER_BINARY" 2>/dev/null || true
    pkill -f "tail -n 0 -F" 2>/dev/null || true
    killall screen 2>/dev/null || true
}

show_status() {
    echo "=== ESTADO DEL SERVIDOR ==="
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Servidor: EJECUTANDOSE"
    else
        echo "Servidor: DETENIDO"
    fi
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot: EJECUTANDOSE"
    else
        echo "Bot: DETENIDO"
    fi
    if [ -f world_id.txt ]; then
        echo "Mundo actual: $(cat world_id.txt)"
    fi
    echo "==========================="
}

case "$1" in
    start)
        if [ -z "$2" ]; then
            echo "Debe indicar WORLD_ID"
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
