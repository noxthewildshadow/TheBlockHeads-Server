#!/usr/bin/env bash
#
# blockheads_installer_interactive.sh
# Instalador interactivo y amigable para The Blockheads server (blockheads_server171)
#
# Uso:
#   sudo ./blockheads_installer_interactive.sh
#
set -euo pipefail

# =========================
# Valores por defecto
# =========================
DEFAULT_SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
DEFAULT_INSTALL_DIR="$(pwd)"
DEFAULT_WORLD_ID="83cad395edb8d0f1912fec89508d8a1d"
DEFAULT_PORT=15151
SERVICE_NAME="blockheads.service"

# =========================
# Helpers
# =========================
_cmd_exists() { command -v "$1" >/dev/null 2>&1; }

prompt_yesno() {
  local prompt="${1:-Continue?}"
  local default="${2:-Y}" # Y or N
  local ans
  while true; do
    if [ "$default" = "Y" ]; then
      read -rp "$prompt [Y/n]: " ans
      ans="${ans:-Y}"
    else
      read -rp "$prompt [y/N]: " ans
      ans="${ans:-N}"
    fi
    case "${ans,,}" in
      y|yes) return 0;;
      n|no) return 1;;
      *) echo "Por favor responde 'y' o 'n'.";;
    esac
  done
}

# Robust download function with fallbacks and informative errors
download_file() {
  local url="$1"
  local dest="$2"

  echo "  Intentando descargar: $url"
  # Try wget (prefer retry and failfast)
  if _cmd_exists wget; then
    echo "    Usando wget..."
    if wget --tries=3 --timeout=20 -O "$dest" "$url"; then
      return 0
    else
      echo "    wget falló (intentando otros métodos)..."
    fi
  fi

  # Try curl
  if _cmd_exists curl; then
    echo "    Usando curl..."
    if curl -fSL --retry 3 --retry-delay 2 -o "$dest" "$url"; then
      return 0
    else
      echo "    curl falló (intentando otros métodos)..."
    fi
  fi

  # Try python3
  if _cmd_exists python3; then
    echo "    Usando python3 para descargar..."
    if python3 - <<PYCODE
import sys, urllib.request
url = "$url"
dest = "$dest"
try:
    urllib.request.urlretrieve(url, dest)
    print("    python3: descarga completada")
    sys.exit(0)
except Exception as e:
    print("    python3: fallo ->", e)
    sys.exit(1)
PYCODE
    then
      return 0
    else
      echo "    python3 fallo (intentando python2)..."
    fi
  fi

  # Try python (python2)
  if _cmd_exists python; then
    echo "    Usando python (2.x) para descargar..."
    if python - <<PYCODE
import sys, urllib
url = "$url"
dest = "$dest"
try:
    urllib.urlretrieve(url, dest)
    print("    python: descarga completada")
    sys.exit(0)
except Exception as e:
    print("    python: fallo ->", e)
    sys.exit(1)
PYCODE
    then
      return 0
    else
      echo "    python (2.x) falló."
    fi
  fi

  # If we reach here, no method worked
  echo "ERROR: No se pudo descargar el archivo. Asegúrate de tener wget o curl o python instalado y acceso a Internet."
  return 1
}

# =========================
# Privilegios root
# =========================
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: este script requiere privilegios de root."
  echo "Ejecuta: sudo $0"
  exit 1
fi

ORIGINAL_USER="${SUDO_USER:-${USER:-root}}"
ORIGINAL_UID=$(id -u "$ORIGINAL_USER" 2>/dev/null || echo 1000)
ORIGINAL_GID=$(id -g "$ORIGINAL_USER" 2>/dev/null || echo 1000)

echo "=========================================="
echo "  Blockheads Installer (interactivo - robusto)"
echo "=========================================="
echo "Usuario que ejecutó sudo: $ORIGINAL_USER"
echo

# =========================
# Preguntas al usuario
# =========================
read -rp "Directorio donde instalar (enter = carpeta actual): " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

read -rp "URL del paquete del servidor (enter = predeterminada): " SERVER_URL
SERVER_URL="${SERVER_URL:-$DEFAULT_SERVER_URL}"

read -rp "World ID (enter = $DEFAULT_WORLD_ID): " WORLD_ID
WORLD_ID="${WORLD_ID:-$DEFAULT_WORLD_ID}"

read -rp "Puerto del servidor (enter = $DEFAULT_PORT): " SERVER_PORT
SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"

echo
echo "Resumen:"
echo "  Carpeta de instalación: $INSTALL_DIR"
echo "  URL del servidor: $SERVER_URL"
echo "  World ID: $WORLD_ID"
echo "  Puerto: $SERVER_PORT"
echo

if ! prompt_yesno "¿Continuar con la instalación?" "Y"; then
  echo "Cancelado por el usuario."
  exit 0
fi

# =========================
# Preparación
# =========================
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/blockheads_server171.tar.gz"
cd "$INSTALL_DIR"

echo
echo "[1/6] Comprobando herramientas necesarias..."
tools_missing=()
for t in wget curl tar file; do
  if ! _cmd_exists "$t"; then
    tools_missing+=("$t")
  fi
done

if [ ${#tools_missing[@]} -gt 0 ]; then
  echo "Nota: faltan algunas utilidades: ${tools_missing[*]}"
  if _cmd_exists apt-get; then
    if prompt_yesno "¿Deseas que el script intente instalar dependencias con apt-get?" "Y"; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y --no-install-recommends "${tools_missing[@]}" || true
    else
      echo "Continúo sin instalar dependencias. Asegúrate manualmente de instalarlas si hay errores."
    fi
  else
    echo "No hay apt-get disponible. Instala manualmente: ${tools_missing[*]}"
  fi
else
  echo "Todas las utilidades necesarias están disponibles."
fi

# =========================
# Descargar (2/6) - robusto
# =========================
echo
echo "[2/6] Descargando servidor..."
if download_file "$SERVER_URL" "$TEMP_FILE"; then
  echo "Descarga completada: $TEMP_FILE"
else
  echo "ERROR: fallo en la descarga. Revisa la URL o la conectividad de red."
  echo "  URL: $SERVER_URL"
  echo "  Archivo destino: $TEMP_FILE"
  echo "  Comprueba si dispones de wget/curl/python y acceso a Internet."
  # limpieza temporal
  rm -rf "$TEMP_DIR" || true
  exit 1
fi

# =========================
# Verificación rápida del archivo descargado (opcional)
# =========================
if _cmd_exists file; then
  mime=$(file --mime-type -b "$TEMP_FILE" || echo "")
  if ! echo "$mime" | grep -q -E "gzip|x-gzip|x-tar"; then
    echo "Advertencia: el archivo descargado no parece un tar.gz (mime: $mime). La extracción puede fallar."
  fi
fi

# =========================
# Extraer (3/6)
# =========================
echo
echo "[3/6] Extrayendo en: $INSTALL_DIR"
if ! tar xzf "$TEMP_FILE" -C "$INSTALL_DIR"; then
  echo "ERROR: extracción fallida. Mostrando contenido del tar (si es posible):"
  tar tzf "$TEMP_FILE" || true
  rm -rf "$TEMP_DIR" || true
  exit 1
fi

SERVER_BINARY="$INSTALL_DIR/blockheads_server171"
if [ ! -f "$SERVER_BINARY" ]; then
  # Buscar binarios extraídos por si vienen en subcarpeta
  maybe=$(find "$INSTALL_DIR" -maxdepth 2 -type f -name 'blockheads_server*' -print -quit || true)
  if [ -n "$maybe" ]; then
    SERVER_BINARY="$maybe"
  fi
fi

if [ ! -f "$SERVER_BINARY" ]; then
  echo "ERROR: No se encontró blockheads_server171 después de extraer. Verifica el contenido del tarball."
  ls -la "$INSTALL_DIR"
  rm -rf "$TEMP_DIR" || true
  exit 1
fi

chmod +x "$SERVER_BINARY"
cp -p "$SERVER_BINARY" "${SERVER_BINARY}.orig" 2>/dev/null || true

# =========================
# Patching con patchelf (4/6) - opcional
# =========================
echo
echo "[4/6] Intentando parchar dependencias (patchelf si está instalado)..."
if _cmd_exists patchelf; then
  replacements=(
    "libgnustep-base.so.1.24:libgnustep-base.so.1.28"
    "libobjc.so.4.6:libobjc.so.4"
    "libgnutls.so.26:libgnutls.so.30"
    "libgcrypt.so.11:libgcrypt.so.20"
    "libffi.so.6:libffi.so.8"
    "libicui18n.so.48:libicui18n.so.70"
    "libicuuc.so.48:libicuuc.so.70"
    "libicudata.so.48:libicudata.so.70"
    "libdispatch.so:libdispatch.so.0"
  )
  for pair in "${replacements[@]}"; do
    oldlib=${pair%%:*}
    newlib=${pair##*:}
    if patchelf --print-needed "$SERVER_BINARY" 2>/dev/null | grep -q "$oldlib"; then
      echo "  Patching $oldlib -> $newlib"
      if patchelf --replace-needed "$oldlib" "$newlib" "$SERVER_BINARY" 2>/dev/null; then
        echo "    OK"
      else
        echo "    Advertencia: fallo al aplicar patchelf para $oldlib -> $newlib (se continúa)"
      fi
    fi
  done
else
  echo "patchelf no está instalado. Si ves errores por librerías faltantes instala patchelf y vuelve a intentar."
fi

# =========================
# Crear start.sh (5/6)
# =========================
echo
echo "[5/6] Creando start.sh amigable en: $INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/start.sh" <<START_SH
#!/usr/bin/env bash
# start.sh generado por blockheads_installer_interactive.sh
set -euo pipefail
# Detectar carpeta del script
DIR="\$(cd "\$(dirname "\$(readlink -f "\$0")")" && pwd)"

# Valores por defecto (puedes sobreescribir con argumentos o editar este archivo)
WORLD_ID="${WORLD_ID}"
PORT=${SERVER_PORT}
RESTART_DELAY=1
MAX_RESTARTS=0  # 0 = ilimitado

LOG_DIR="\$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/\$WORLD_ID"
LOG_FILE="\$LOG_DIR/console.log"
SERVER_BINARY="\$DIR/$(basename "$SERVER_BINARY")"

usage() {
  cat <<EOF
Uso: \$0 [--world <id>] [--port <port>] [--no-restart] [--help]
Opciones:
  --world <id>     : cambiar world id para esta ejecución
  --port <port>    : cambiar puerto para esta ejecución
  --no-restart     : ejecutar el servidor una vez (sin reiniciar automáticamente)
  --help           : mostrar esta ayuda
EOF
}

NO_RESTART=false
while [ \$# -gt 0 ]; do
  case "\$1" in
    --world) WORLD_ID="\$2"; shift 2;;
    --port) PORT="\$2"; shift 2;;
    --no-restart) NO_RESTART=true; shift;;
    --help) usage; exit 0;;
    *) echo "Opción desconocida: \$1"; usage; exit 1;;
  esac
done

mkdir -p "\$LOG_DIR"
chmod 755 "\$LOG_DIR" || true

if [ ! -f "\$SERVER_BINARY" ]; then
  echo "Error: no se encontró el binario \$SERVER_BINARY"
  exit 1
fi
if [ ! -x "\$SERVER_BINARY" ]; then
  chmod +x "\$SERVER_BINARY" || true
fi

echo "Iniciando The Blockheads Server"
echo " World: \$WORLD_ID"
echo " Port: \$PORT"
echo " Log: \$LOG_FILE"
echo " (Ctrl+C para salir)"
echo "-----------------------------------------"

restart_count=0
terminate_loop=false
trap 'terminate_loop=true' SIGINT SIGTERM

run_server() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecutando servidor..." | tee -a "\$LOG_FILE"
  (cd "\$(dirname "\$SERVER_BINARY")" && "\$SERVER_BINARY" -o "\$WORLD_ID" -p "\$PORT") 2>&1 | tee -a "\$LOG_FILE"
  return \${PIPESTATUS[0]:-0}
}

if [ "\$NO_RESTART" = true ]; then
  run_server
  exit_code=\$?
  echo "Servidor finalizó (exit code: \$exit_code)"
  exit \$exit_code
fi

while true; do
  restart_count=\$((restart_count + 1))
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Inicio (restart #\$restart_count)" | tee -a "\$LOG_FILE"
  run_server
  exit_code=\$?
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Servidor salió (exit code: \$exit_code)" | tee -a "\$LOG_FILE"

  if [ "\$terminate_loop" = true ]; then
    echo "Shutdown solicitado. Saliendo del bucle." | tee -a "\$LOG_FILE"
    break
  fi

  echo "Reiniciando en \$RESTART_DELAY s..." | tee -a "\$LOG_FILE"
  sleep "\$RESTART_DELAY"
done

echo "Bucle terminado."
START_SH

chmod 755 "$INSTALL_DIR/start.sh"
chown "$ORIGINAL_UID:$ORIGINAL_GID" "$INSTALL_DIR/start.sh" "$SERVER_BINARY" || true

# =========================
# systemd opcional
# =========================
echo
if _cmd_exists systemctl && prompt_yesno "¿Deseas que cree un servicio systemd para gestionar el servidor automáticamente (arranque, logs, start/stop)?" "Y"; then
  SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=The Blockheads Server
After=network.target

[Service]
Type=simple
User=$ORIGINAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=HOME=/home/$ORIGINAL_USER

[Install]
WantedBy=multi-user.target
SERVICE

  chmod 644 "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" || true
  echo "Servicio systemd creado en $SERVICE_FILE y habilitado (no iniciado aún)."
  if prompt_yesno "¿Iniciar el servicio ahora?" "Y"; then
    systemctl start "$SERVICE_NAME" || true
    echo "Servicio iniciado. Comprueba estado con: sudo systemctl status $SERVICE_NAME"
  else
    echo "Puedes iniciar el servicio más tarde con: sudo systemctl start $SERVICE_NAME"
  fi
else
  echo "Se omite la creación de servicio systemd."
fi

# =========================
# Limpieza y verificación final (6/6)
# =========================
rm -rf "$TEMP_DIR" || true

echo
echo "=========================================="
echo "Instalación finalizada."
echo "  Carpeta: $INSTALL_DIR"
echo "  Ejecutable: $(basename "$SERVER_BINARY")"
echo "  Inicia el servidor con: $INSTALL_DIR/start.sh"
echo "  O si creaste el servicio: sudo systemctl start $SERVICE_NAME"
echo
echo "Ver logs en tiempo real:"
echo "  - Si usas start.sh: verás salida por pantalla (y además se guarda en ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/<world_id>/console.log)."
echo "  - Si usas systemd: sudo journalctl -u $SERVICE_NAME -f"
echo
echo "Consejos:"
echo "  - Edita $INSTALL_DIR/start.sh si quieres cambiar world_id o puerto de forma permanente."
echo "  - Para detener el servicio systemd: sudo systemctl stop $SERVICE_NAME"
echo "=========================================="
