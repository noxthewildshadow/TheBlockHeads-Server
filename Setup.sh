#!/usr/bin/env bash

# Script de instalación para The Blockheads Server
# Ejecutar con: curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/main/Setup.sh | sudo bash

set -euo pipefail
trap 'echo "Error en la línea $LINENO. Abortando." >&2' ERR

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funciones para imprimir mensajes
print_status()  { echo -e "${GREEN}[+]${NC} $1"; }
print_error()   { echo -e "${RED}[-]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Verificar si estamos en Ubuntu 22.04 (advertir si no)
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "No se puede determinar la distribución de Linux"
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
        print_warning "Este script está optimizado para Ubuntu 22.04. Puede que no funcione correctamente en otras distribuciones."
        if [[ -z "${FORCE_CONTINUE:-}" ]]; then
            read -p "¿Continuar de todos modos? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            print_status "Continuando por variable FORCE_CONTINUE..."
        fi
    fi
}

# Instalar dependencias necesarias
install_dependencies() {
    print_status "Instalando dependencias del sistema..."
    apt-get update -y
    apt-get install -y curl patchelf libgnustep-base1.28 libobjc4 libgnutls30 libgcrypt20 libffi8 libicu70 libdispatch0
}

# Configurar el directorio de mundos (REEMPLAZADA según petición)
setup_worlds_directory() {
    print_status "Configurando directorio de mundos..."

    # Determinar el home del usuario que ejecutó sudo (o usar $HOME si no)
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        USER_HOME="$HOME"
    fi

    BASE_DIR="$USER_HOME/GNUstep/Library/ApplicationSupport/TheBlockheads"
    SAVES_UPPER="$BASE_DIR/Saves"
    SAVES_LOWER="$BASE_DIR/saves"

    # Si existe "saves" (minúsculas) y no existe "Saves", moverlo a la forma correcta
    if [[ -d "$SAVES_LOWER" && ! -d "$SAVES_UPPER" ]]; then
        print_status "Se encontró '$SAVES_LOWER'. Moviendo a '$SAVES_UPPER'..."
        mkdir -p "$BASE_DIR"
        mv "$SAVES_LOWER" "$SAVES_UPPER" || {
            print_warning "No se pudo mover '$SAVES_LOWER' a '$SAVES_UPPER' automáticamente."
        }
    fi

    # Asegurar existencia de la carpeta con la capitalización correcta
    mkdir -p "$SAVES_UPPER"

    # Ajustar propietario si se ejecutó con sudo
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/GNUstep"
    fi

    WORLD_DIR="$SAVES_UPPER"
    print_status "Mundos ubicados en: $WORLD_DIR"
}

# Descargar y configurar el servidor
setup_server() {
    print_status "Creando directorio para el servidor..."
    mkdir -p /opt/blockheads-server
    cd /opt/blockheads-server

    print_status "Descargando el servidor de The Blockheads..."
    # URL de ejemplo: si el enlace cambia, reemplazar por uno válido
    SERVER_TAR_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"

    # Descargar y extraer desde stdin
    if ! curl -sL "$SERVER_TAR_URL" | tar -xzf - -C ./; then
        print_error "Error al descargar o extraer el paquete desde: $SERVER_TAR_URL"
        exit 1
    fi

    # Intentar localizar el binario (nombre esperado: blockheads_server171)
    if [[ ! -f "blockheads_server171" ]]; then
        # buscar cualquier binario plausible
        BIN_CANDIDATE=$(find . -maxdepth 2 -type f -iname "blockheads_*" -print -quit || true)
        if [[ -n "$BIN_CANDIDATE" ]]; then
            mv "$BIN_CANDIDATE" ./blockheads_server171
        fi
    fi

    if [[ ! -f "blockheads_server171" ]]; then
        print_error "Error: El binario blockheads_server171 no se encontró tras la extracción."
        ls -la
        exit 1
    fi

    print_status "Aplicando parches al binario (si son necesarios)..."
    # Aplicar parches de forma no fatal
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171 2>/dev/null || true
    patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171 2>/dev/null || true

    chmod +x blockheads_server171

    # Verificación final
    if [[ ! -x "blockheads_server171" ]]; then
        print_error "Error: El binario blockheads_server171 no es ejecutable"
        exit 1
    fi

    # Configurar directorio de mundos
    setup_worlds_directory
}

# Crear script de gestión de mundos
create_management_script() {
    print_status "Creando script de gestión de mundos..."

    SERVER_DIR="/opt/blockheads-server"
    SERVER_BIN="$SERVER_DIR/blockheads_server171"

    cat > /usr/local/bin/blockheads <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR="/opt/blockheads-server"
SERVER_BIN="$SERVER_DIR/blockheads_server171"

print() { echo -e "$@"; }
print_error() { echo -e "\e[31m[!] $*\e[0m" >&2; }

# Detectar el directorio de mundos correcto (Saves vs saves)
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    MGMT_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    MGMT_USER_HOME="$HOME"
fi
POSSIBLE_BASE="$MGMT_USER_HOME/GNUstep/Library/ApplicationSupport/TheBlockheads"
if [[ -d "$POSSIBLE_BASE/Saves" ]]; then
    WORLD_DIR="$POSSIBLE_BASE/Saves"
elif [[ -d "$POSSIBLE_BASE/saves" ]]; then
    # Si todavía existe la lowercase por cualquier motivo, usarla (compatibilidad)
    WORLD_DIR="$POSSIBLE_BASE/saves"
else
    # Preferir la capitalización correcta por defecto
    WORLD_DIR="$POSSIBLE_BASE/Saves"
fi

# show_help
show_help() {
    cat <<HEREDOC
Uso: blockheads [COMANDO] [ARGUMENTOS]

Comandos:
  create <NOMBRE_MUNDO> [OPCIONES]  Crear un nuevo mundo
  start <ID_O_NOMBRE> [PUERTO]      Iniciar un mundo existente
  list                              Listar todos los mundos
  delete <ID_O_NOMBRE>              Eliminar un mundo
  debug-list                         Mostrar salida completa de --list (para debug)
  help                              Mostrar esta ayuda

Opciones para create:
  -p, --port PORT                   Puerto del servidor (por defecto: 15151)
  -m, --max-players MAX             Máximo de jugadores (por defecto: 16, máximo: 32)
  -w, --world-width TAMAÑO          Tamaño del mundo (1/16, 1/4, 1, 4, 16)
  -e, --expert-mode                 Habilitar modo experto
HEREDOC
}

# get_world_info: devuelve la salida de --list
get_world_info() {
    (cd "$SERVER_DIR" && "$SERVER_BIN" --list) 2>/dev/null || true
}

# get_world_id_by_name: busca por nombre (case-insensitive), devuelve el primer ID encontrado
get_world_id_by_name() {
    local world_name="$1"
    local world_info
    world_info=$(get_world_info)

    # Leer línea por línea sin crear subshell
    while IFS= read -r line; do
        # separar primer campo (id) del resto (nombre)
        id=$(awk '{print $1}' <<< "$line")
        name=$(awk '{$1=""; sub(/^ /,""); print}' <<< "$line")
        if [[ -z "$id" ]]; then
            continue
        fi
        # comparar en minúsculas para permitir coincidencias case-insensitive
        if [[ "${name,,}" == *"${world_name,,}"* ]]; then
            printf "%s\n" "$id"
            return 0
        fi
    done <<< "$world_info"

    return 1
}

# world_exists: comprueba si el ID existe en la lista
world_exists() {
    local world_id="$1"
    local world_info
    world_info=$(get_world_info)
    if awk '{print $1}' <<< "$world_info" | grep -Eq "^${world_id}\$"; then
        return 0
    else
        return 1
    fi
}

# create_world
create_world() {
    local world_name="$1"
    shift
    local extra_args=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port) extra_args="$extra_args --port $2"; shift 2 ;;
            -m|--max-players) extra_args="$extra_args --max_players $2"; shift 2 ;;
            -w|--world-width) extra_args="$extra_args --world_width $2"; shift 2 ;;
            -e|--expert-mode) extra_args="$extra_args --expert-mode"; shift ;;
            *) print_error "Opción desconocida: $1"; exit 1 ;;
        esac
    done

    (cd "$SERVER_DIR" && "$SERVER_BIN" --new "$world_name" $extra_args)
    sleep 1
    local world_id
    if world_id=$(get_world_id_by_name "$world_name"); then
        echo "Mundo creado con éxito. ID: $world_id"
        echo "Para iniciarlo: blockheads start $world_id"
    else
        print_error "Error: No se pudo determinar el ID del mundo creado."
        exit 1
    fi
}

# start_world
start_world() {
    local world_identifier="$1"
    local port="${2:-15151}"
    local world_id=""

    if [[ "$world_identifier" =~ ^[0-9a-fA-F]+$ ]]; then
        world_id="$world_identifier"
    else
        if ! world_id=$(get_world_id_by_name "$world_identifier"); then
            print_error "Error: No existe un mundo con nombre '$world_identifier'"
            exit 1
        fi
    fi

    if ! world_exists "$world_id"; then
        print_error "Error: No existe un mundo con ID $world_id"
        exit 1
    fi

    echo "Iniciando mundo ID: $world_id en puerto: $port"
    cd "$SERVER_DIR"
    exec "$SERVER_BIN" --load "$world_id" --port "$port" --no-exit
}

# list_worlds
list_worlds() {
    (cd "$SERVER_DIR" && "$SERVER_BIN" --list) || true
}

# delete_world
delete_world() {
    local world_identifier="$1"
    local world_id=""

    if [[ "$world_identifier" =~ ^[0-9a-fA-F]+$ ]]; then
        world_id="$world_identifier"
    else
        if ! world_id=$(get_world_id_by_name "$world_identifier"); then
            print_error "Error: No existe un mundo con nombre '$world_identifier'"
            exit 1
        fi
    fi

    if ! world_exists "$world_id"; then
        print_error "Error: No existe un mundo con ID $world_id"
        exit 1
    fi

    read -r -p "¿Estás seguro de que quieres eliminar el mundo ID: $world_id? (y/N): " reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        echo "Operación cancelada."
        exit 0
    fi

    (cd "$SERVER_DIR" && "$SERVER_BIN" --delete "$world_id" --force)
    echo "Mundo eliminado: $world_id"
}

# Command dispatch
case "${1:-help}" in
    create) shift; if [[ -z "${1:-}" ]]; then print_error "Se requiere un nombre para el mundo"; exit 1; fi; create_world "$@" ;;
    start) shift; if [[ -z "${1:-}" ]]; then print_error "Se requiere el ID o nombre de un mundo"; exit 1; fi; start_world "$@" ;;
    list) list_worlds ;;
    delete) shift; if [[ -z "${1:-}" ]]; then print_error "Se requiere el ID o nombre de un mundo"; exit 1; fi; delete_world "$1" ;;
    debug-list) get_world_info ;;
    help|*) show_help ;;
esac
EOF

    chmod +x /usr/local/bin/blockheads
}

# Crear script de desinstalación
create_uninstall_script() {
    print_status "Creando script de desinstalación..."
    cat > /usr/local/bin/blockheads-uninstall <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Desinstalando The Blockheads Server..."
rm -rf /opt/blockheads-server
rm -f /usr/local/bin/blockheads
rm -f /usr/local/bin/blockheads-uninstall
echo "Servidor desinstalado correctamente."
EOF
    chmod +x /usr/local/bin/blockheads-uninstall
}

# Función principal
main() {
    print_status "Iniciando instalación de The Blockheads Server..."

    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse con privilegios de root. Use sudo."
        exit 1
    fi

    check_ubuntu_version
    install_dependencies
    setup_server
    create_management_script
    create_uninstall_script

    print_status "Instalación completada!"
    echo ""
    echo "Para crear un nuevo mundo:"
    echo "  blockheads create NOMBRE_MUNDO [OPCIONES]"
    echo ""
    echo "Para iniciar un mundo existente:"
    echo "  blockheads start ID_MUNDO [PUERTO]"
    echo ""
    echo "Para listar todos los mundos:"
    echo "  blockheads list"
    echo ""
    echo "Para debug (ver salida real de --list):"
    echo "  blockheads debug-list"
    echo ""
    echo "El servidor se ha instalado en: /opt/blockheads-server"
    echo "Los mundos (Saves) se almacenan en: ~/GNUstep/Library/ApplicationSupport/TheBlockheads/Saves/"
}

# Ejecutar función principal
main "$@"
