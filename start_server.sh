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

# Función para liberar el puerto
free_port() {
    local port="$1"
    echo "Intentando liberar el puerto $port..."
    
    # Matar procesos usando el puerto
    local pids=$(lsof -ti ":$port")
    if [ -n "$pids" ]; then
        echo "Encontrados procesos usando el puerto $port: $pids"
        kill -9 $pids 2>/dev/null || true
        sleep 2
    fi
    
    # Matar todas las sesiones de screen para evitar conflictos
    killall screen 2>/dev/null || true
    
    # Verificar si el puerto quedó libre
    if is_port_in_use "$port"; then
        echo "ERROR: No se pudo liberar el puerto $port"
        return 1
    else
        echo "Puerto $port liberado correctamente"
        return 0
    fi
}

# Función para verificar si el mundo existe
check_world_exists() {
    local world_id="$1"
    local saves_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves"
    local world_dir="$saves_dir/$world_id"
    
    if [ ! -d "$world_dir" ]; then
        echo "Error: El mundo '$world_id' no existe."
        echo "Primero crea un mundo con: ./blockheads_server171 -n"
        return 1
    fi
    
    return 0
}

# Función para iniciar el servidor
start_server() {
    local world_id="$1"
    local port="${2:-$DEFAULT_PORT}"
    
    # Verificar y liberar el puerto primero
    if is_port_in_use "$port"; then
        echo "El puerto $port está en uso."
        if ! free_port "$port"; then
            echo "No se puede iniciar el servidor. El puerto $port no está disponible."
            return 1
        fi
    fi
    
    # Limpiar sesiones de screen existentes
    killall screen 2>/dev/null || true
    sleep 1
    
    if ! check_world_exists "$world_id"; then
        return 1
    fi
    
    # Crear directorio de logs si no existe
    local log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
    local log_file="$log_dir/console.log"
    mkdir -p "$log_dir"
    
    echo "Iniciando servidor con mundo: $world_id, puerto: $port"
    
    # Guardar world_id para futuros usos
    echo "$world_id" > world_id.txt
    
    # Iniciar servidor en screen con reinicio automático
    screen -dmS "$SCREEN_SERVER" bash -c "
        while true; do
            echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando servidor...\"
            if $SERVER_BINARY -o '$world_id' -p $port 2>&1 | tee -a '$log_file'; then
                echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Servidor cerrado normalmente.\"
            else
                exit_code=\$?
                echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Servidor falló con código: \$exit_code\"
                # Verificar si es un error de puerto en uso
                if [ \$exit_code -eq 1 ] && tail -n 5 '$log_file' | grep -q \"port.*already in use\"; then
                    echo \"[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Puerto ya en uso. No se reintentará.\"
                    break
                fi
            fi
            echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Reiniciando en 5 segundos...\"
            sleep 5
        done
    "
    
    # Esperar a que el archivo de log exista
    echo "Esperando a que el servidor inicie..."
    local wait_time=0
    while [ ! -f "$log_file" ] && [ $wait_time -lt 10 ]; do
        sleep 1
        ((wait_time++))
    done
    
    if [ ! -f "$log_file" ]; then
        echo "ERROR: No se pudo crear el archivo de log. El servidor puede no haber iniciado."
        return 1
    fi
    
    # Verificar si el servidor inició correctamente
    if grep -q "Failed to start server\|port.*already in use" "$log_file"; then
        echo "ERROR: El servidor no pudo iniciarse. Verifique el puerto $port."
        return 1
    fi
    
    # Iniciar el bot después de que el servidor esté listo
    start_bot "$log_file"
    
    echo "Servidor iniciado correctamente."
    echo "Para ver la consola: screen -r $SCREEN_SERVER"
    echo "Para ver el bot: screen -r $SCREEN_BOT"
}

# Función para iniciar el bot
start_bot() {
    local log_file="$1"
    
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "El bot ya está ejecutándose."
        return 0
    fi
    
    # Esperar a que el servidor esté completamente iniciado
    echo "Esperando a que el servidor esté listo..."
    sleep 5
    
    # Iniciar bot en screen separada
    screen -dmS "$SCREEN_BOT" bash -c "
        echo 'Iniciando bot del servidor...'
        ./bot_server.sh '$log_file'
    "
    
    echo "Bot iniciado correctamente."
}

# Función para detener todo
stop_server() {
    # Detener servidor
    if screen -list | grep -q "$SCREEN_SERVER"; then
        screen -S "$SCREEN_SERVER" -X quit
        echo "Servidor detenido."
    else
        echo "El servidor no estaba ejecutándose."
    fi
    
    # Detener bot
    if screen -list | grep -q "$SCREEN_BOT"; then
        screen -S "$SCREEN_BOT" -X quit
        echo "Bot detenido."
    else
        echo "El bot no estaba ejecutándose."
    fi
    
    # Limpiar procesos residuales
    pkill -f "$SERVER_BINARY" 2>/dev/null || true
    pkill -f "tail -n 0 -F" 2>/dev/null || true
    
    # Limpiar sesiones de screen
    killall screen 2>/dev/null || true
}

# Función para mostrar estado
show_status() {
    echo "=== ESTADO DEL SERVIDOR THE BLOCKHEADS ==="
    
    # Verificar servidor
    if screen -list | grep -q "$SCREEN_SERVER"; then
        echo "Servidor: EJECUTÁNDOSE"
    else
        echo "Servidor: DETENIDO"
    fi
    
    # Verificar bot
    if screen -list | grep -q "$SCREEN_BOT"; then
        echo "Bot: EJECUTÁNDOSE"
    else
        echo "Bot: DETENIDO"
    fi
    
    # Mostrar información del mundo si existe
    if [ -f "world_id.txt" ]; then
        WORLD_ID=$(cat world_id.txt)
        echo "Mundo actual: $WORLD_ID"
        
        # Mostrar información de jugadores si el servidor está ejecutándose
        if screen -list | grep -q "$SCREEN_SERVER"; then
            echo "Para ver la consola: screen -r $SCREEN_SERVER"
            echo "Para ver el bot: screen -r $SCREEN_BOT"
        fi
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
