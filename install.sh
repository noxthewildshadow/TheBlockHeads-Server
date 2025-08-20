#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# install_blockheads.sh
# Instalador mejorado para The Blockheads server (blockheads_server171)
# Uso: sudo bash install_blockheads.sh
# -----------------------------------------------------------------------------

# --- Configuración ---
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
START_SCRIPT_URL="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/start.sh"
INSTALL_DIR="/opt/blockheads_server171"
SERVER_BINARY_NAME="blockheads_server171"

# --- Utilidades ---
log() { echo "[install] $*"; }
err() { echo "[install][ERROR] $*" >&2; }
check_cmd() {
    command -v "$1" >/dev/null 2>&1 || { err "Comando requerido no encontrado: $1"; return 1; }
}
cleanup() {
    # Limpia temporales si existen
    [[ -n "${TMP_TAR:-}" && -f "$TMP_TAR" ]] && rm -f "$TMP_TAR" || true
}
trap cleanup EXIT

# --- Comprobaciones previas ---
if [[ $EUID -ne 0 ]]; then
    err "Este script requiere privilegios de root. Ejecuta: sudo $0"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
if ! id "$ORIGINAL_USER" >/dev/null 2>&1; then
    err "No se pudo identificar al usuario original (SUDO_USER)."
    exit 1
fi

log "Usuario de instalación: $ORIGINAL_USER"
log "Directorio de instalación: $INSTALL_DIR"

# Comprueba que el sistema es Debian/Ubuntu (típico)
if ! check_cmd apt-get; then
    err "No se detectó apt-get. Este instalador está pensado para Debian/Ubuntu."
    exit 1
fi

# Instalar paquetes necesarios (silencioso pero informativo)
log "Instalando dependencias necesarias (software-properties-common, wget, tar, patchelf)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y software-properties-common wget tar patchelf ca-certificates || {
    err "Error instalando paquetes. Revisa tu conexión o los repositorios."
    exit 1
}

# Crear directorio de instalación
log "Creando directorio de instalación..."
mkdir -p "$INSTALL_DIR"
chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Descargar servidor (a /tmp)
TMP_TAR="$(mktemp -u)/blockheads_server171.tar.gz"
TMP_TAR="$(mktemp)"
log "Descargando servidor desde: $SERVER_URL"
if ! wget -q --inet4-only --timeout=30 -O "$TMP_TAR" "$SERVER_URL"; then
    err "Fallo al descargar el servidor. Revisa la URL o la conexión."
    exit 1
fi

# Extraer en INSTALL_DIR
log "Extrayendo archivos en $INSTALL_DIR ..."
if ! tar xzf "$TMP_TAR" -C "$INSTALL_DIR"; then
    err "Fallo al extraer el tar.gz."
    exit 1
fi

# Busca el binario dentro de INSTALL_DIR; si no existe, intentar mover/renombrar
if [[ -f "$INSTALL_DIR/$SERVER_BINARY_NAME" ]]; then
    SERVER_BINARY_PATH="$INSTALL_DIR/$SERVER_BINARY_NAME"
else
    # intenta localizar primer binario ejecutable encontrado en el directorio extraído
    found=$(find "$INSTALL_DIR" -maxdepth 2 -type f -executable -printf '%p\n' | head -n1 || true)
    if [[ -n "$found" ]]; then
        log "Se encontró binario en: $found — lo renombraré a $SERVER_BINARY_NAME"
        mv "$found" "$INSTALL_DIR/$SERVER_BINARY_NAME"
        SERVER_BINARY_PATH="$INSTALL_DIR/$SERVER_BINARY_NAME"
    else
        err "No se encontró el binario $SERVER_BINARY_NAME dentro del paquete."
        exit 1
    fi
fi

# Asegurar permisos y propietario
chown "$ORIGINAL_USER":"$ORIGINAL_USER" -R "$INSTALL_DIR"
chmod 755 "$SERVER_BINARY_PATH"

# Descargar start.sh (opcional: colocarlo en INSTALL_DIR)
log "Descargando script de inicio (start.sh)..."
if ! wget -q --inet4-only --timeout=20 -O "$INSTALL_DIR/start.sh" "$START_SCRIPT_URL"; then
    log "Advertencia: no se pudo descargar start.sh desde el repositorio remoto. Crealo manualmente si lo necesitas."
else
    chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$INSTALL_DIR/start.sh"
    chmod 755 "$INSTALL_DIR/start.sh"
fi

# --- Parches con patchelf (condicional) ---
log "Intentando aplicar parches de compatibilidad con patchelf (solo si aplica)."
if ! check_cmd patchelf; then
    log "patchelf no está disponible; saltando parches binarios."
else
    # Helper para reemplazar si está en la lista de NEEDED
    do_replace_needed() {
        local old="$1" new="$2" bin="$3"
        if patchelf --print-needed "$bin" 2>/dev/null | grep -Fq "$old"; then
            log "Reemplazando $old -> $new en $bin"
            patchelf --replace-needed "$old" "$new" "$bin" || log "patchelf fallo al reemplazar $old -> $new"
        else
            log "No es necesario reemplazar $old en $bin"
        fi
    }

    do_replace_needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY_PATH"
    do_replace_needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY_PATH"
    do_replace_needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY_PATH"
    do_replace_needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY_PATH"
    do_replace_needed libffi.so.6 libffi.so.8 "$SERVER_BINARY_PATH"
    do_replace_needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY_PATH"
    do_replace_needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY_PATH"
    do_replace_needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY_PATH"
    do_replace_needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY_PATH"
fi

# --- Finalización ---
log "Limpieza de temporales..."
cleanup

log "Instalación completada."
echo "  Directorio de instalación: $INSTALL_DIR"
echo "  Binario: $SERVER_BINARY_PATH"
echo "  Para iniciar: ejecuta start.sh dentro de $INSTALL_DIR como el usuario normal (no root)."
echo ""
echo "Sugerencia (recomendada): crea un servicio systemd para ejecutar el servidor automáticamente."
echo "Si quieres, puedo darte un ejemplo de unit file para systemd (te lo dejaré al final)."

# Verificación rápida del binario
if "$SERVER_BINARY_PATH" --help >/dev/null 2>&1; then
    log "Verificación: el binario respondió correctamente a --help"
else
    log "Advertencia: el binario no respondió correctamente a --help. Puede haber problemas de compatibilidad; revisa los logs."
fi

exit 0
