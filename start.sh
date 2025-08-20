#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# start_blockheads_server.sh
# Script de arranque que mantiene el servidor en loop, con logs y rotación simple.
# Ejecución recomendada: como usuario normal (no root).
# Uso: cd /opt/blockheads_server171 && ./start_blockheads_server.sh
# -----------------------------------------------------------------------------

# ---------- Configuración (ajusta aquí) ----------
WORLD_ID="${WORLD_ID:-83cad395edb8d0f1912fec89508d8a1d}"
SERVER_PORT="${SERVER_PORT:-15151}"
INSTALL_DIR="${INSTALL_DIR:-/opt/blockheads_server171}"
SERVER_BINARY_PATH="${SERVER_BINARY_PATH:-$INSTALL_DIR/blockheads_server171}"
LOG_DIR_RELATIVE="GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$WORLD_ID"
MAX_LOG_SIZE_BYTES="${MAX_LOG_SIZE_BYTES:-104857600}"  # 100 MB rotación simple
RESTART_DELAY_SEC="${RESTART_DELAY_SEC:-1}"

# ---------- Determinar usuario y home para logs ----------
# Si el script se ejecuta mediante sudo, preferimos el SUDO_USER para la carpeta de logs
if [[ -n "${SUDO_USER:-}" ]]; then
    RUN_USER="$SUDO_USER"
else
    RUN_USER="$(id -un)"
fi

# Obtener home real del usuario (funciona aunque $HOME apunte a root)
USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
if [[ -z "${USER_HOME:-}" ]]; then
    echo "[start][ERROR] No se pudo determinar el home del usuario $RUN_USER"
    exit 1
fi

LOG_DIR="$USER_HOME/$LOG_DIR_RELATIVE"
LOG_FILE="$LOG_DIR/console.log"

# ---------- Comprobaciones ----------
if [[ ! -f "$SERVER_BINARY_PATH" ]]; then
    echo "[start][ERROR] No se encontró el binario en $SERVER_BINARY_PATH"
    echo "Ejecuta el instalador o corrige INSTALL_DIR/SERVER_BINARY_PATH."
    exit 1
fi

if [[ ! -x "$SERVER_BINARY_PATH" ]]; then
    echo "[start] Estableciendo permisos de ejecución en $SERVER_BINARY_PATH"
    chmod +x "$SERVER_BINARY_PATH"
fi

# Crear directorio de logs si no existe
if [[ ! -d "$LOG_DIR" ]]; then
    echo "[start] Creando directorio de logs: $LOG_DIR"
    mkdir -p "$LOG_DIR"
    chown "$RUN_USER":"$RUN_USER" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
fi

# Rotación muy simple: si el archivo supera MAX_LOG_SIZE_BYTES lo renombramos con timestamp
rotate_logs_if_needed() {
    if [[ -f "$LOG_FILE" ]]; then
        size=$(stat -c%s "$LOG_FILE" || echo 0)
        if (( size >= MAX_LOG_SIZE_BYTES )); then
            ts=$(date +'%Y%m%d-%H%M%S')
            mv "$LOG_FILE" "$LOG_DIR/console.log.$ts"
            chown "$RUN_USER":"$RUN_USER" "$LOG_DIR/console.log.$ts"
            echo "[start] Rotado log antiguo a console.log.$ts"
        fi
    fi
}

echo "============================================"
echo "Starting The Blockheads Server"
echo "World ID: $WORLD_ID"
echo "Port: $SERVER_PORT"
echo "Log: $LOG_FILE"
echo "Running as user: $RUN_USER (home: $USER_HOME)"
echo "============================================"

# Bucle principal que reinicia el servidor si se cae
restart_count=0
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    rotate_logs_if_needed

    # Asegurarse que el log existe y pertenezca al usuario
    touch "$LOG_FILE"
    chown "$RUN_USER":"$RUN_USER" "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    echo "[$timestamp] Starting server (restart #$restart_count)" >> "$LOG_FILE"

    # Ejecutar el binario. Se recomienda ejecutarlo bajo el usuario correcto, si éste no coincide este script
    # está pensado para correr directamente como ese usuario. Si estás como root, no suplantamos por seguridad.
    # Redirigimos stdout/stderr al log.
    ( cd "$INSTALL_DIR" && exec "$SERVER_BINARY_PATH" -o "$WORLD_ID" -p "$SERVER_PORT" >> "$LOG_FILE" 2>&1 )
    exit_code=$?

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Server closed (exit code: $exit_code), restarting in ${RESTART_DELAY_SEC}s..." >> "$LOG_FILE"

    sleep "$RESTART_DELAY_SEC"
done
