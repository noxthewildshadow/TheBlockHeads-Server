#!/usr/bin/env bash

# Script de instalación para The Blockheads Server
# Ejecutar con: curl -sSL <tu_url>/Setup.sh | sudo bash

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

# Configurar el directorio de mundos (REEMPLAZADA para mover saves -> Saves)
setup_worlds_directory() {
    print_status "Configurando directorio de mundos..."

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        USER_HOME="$HOME"
    fi

    BASE_DIR="$USER_HOME/GNUstep/Library/ApplicationSupport/TheBlockheads"
    SAVES_UPPER="$BASE_DIR/Saves"
    SAVES_LOWER="$BASE_DIR/saves"

    if [[ -d "$SAVES_LOWER" && ! -d "$SAVES_UPPER" ]]; then
        print_status "Se encontró '$SAVES_LOWER'. Moviendo a '$SAVES_UPPER'..."
        mkdir -p "$BASE_DIR"
        mv "$SAVES_LOWER" "$SAVES_UPPER" || {
            print_warning "No se pudo mover '$SAVES_LOWER' a '$SAVES_UPPER' automáticamente."
        }
    fi

    mkdir -p "$SAVES_UPPER"

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/GNUstep" 2>/dev/null || true
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
    SERVER_TAR_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"

    if ! curl -sL "$SERVER_TAR_URL" | tar -xzf - -C ./; then
        print_error "Error al descargar o extraer el paquete desde: $SERVER_TAR_URL"
        exit 1
    fi

    if [[ ! -f "blockheads_server171" ]]; then
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

    if [[ ! -x "blockheads_server171" ]]; then
        print_error "Error: El binario blockheads_server171 no es ejecutable"
        exit 1
    fi

    setup_worlds_directory
}

# Crear script de gestión de mundos (mejor parsing de --list)
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
    WORLD_DIR="$POSSIBLE_BASE/saves"
else
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
  debug-list                        Mostrar salida completa de --list (para debug)
  help                              Mostrar esta ayuda

Opciones para create:
  -p, --port PORT                   Puerto del servidor (por defecto: 15151)
  -m, --max-players MAX             Máximo de jugadores (por defecto: 16, máximo: 32)
  -w, --world-width TAMAÑO          Tamaño del mundo (1/16, 1/4, 1, 4, 16)
  -e, --expert-mode                 Habilitar modo experto
HEREDOC
}

# get_world_info: devuelve la salida de --list (sin modificarla)
get_world_info() {
    (cd "$SERVER_DIR" && "$SERVER_BIN" --list) 2>/dev/null || true
}

# get_world_id_by_name: busca por nombre (case-insensitive) y extrae IDs hex de 32 caracteres
get_world_id_by_name() {
    local world_name="$1"
    local world_info
    world_info=$(get_world_info)

    # leer cada línea e intentar extraer ID (32 hex) y nombre (si está entre comillas)
    while IFS= read -r line; do
        # extraer primer ID hex de 32 chars si existe
        id=$(grep -Eo '([0-9a-fA-F]{32})' <<< "$line" | head -n1 || true)

        # obtener nombre si está entre comillas dobles
        name=""
        if [[ $line =~ \"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ $line =~ \'([^\']+)\' ]]; then
            name="${BASH_REMATCH[1]}"
        else
            # fallback: texto antes de "stored" o "named" u "in directory"
            name=$(awk -F" stored| named| in directory| on port|, " '{print $1}' <<< "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi

        # si el nombre coincide parcialmente (case-insensitive) y hay id, devolver id
        if [[ -n "$id" && -n "$name" && "${name,,}" == *"${world_name,,}"* ]]; then
            printf "%s\n" "$id"
            return 0
        fi

        # si el user pasó directamente un id (32 hex) que coincide con id de la línea, devolverlo
        if [[ "$world_name" =~ ^[0-9a-fA-F]{32}$ ]]; then
            if [[ -n "$id" && "${id,,}" == "${world_name,,}" ]]; then
                printf "%s\n" "$id"
                return 0
            fi
        fi
    done <<< "$world_info"

    # como último recurso: si world_name es id y aparece en cualquier parte de la salida, devolverla
    if [[ "$world_name" =~ ^[0-9a-fA-F]{32}$ ]] && grep -Eq "${world_name}" <<< "$world_info"; then
        printf "%s\n" "$world_name"
        return 0
    fi

    return 1
}

# world_exists: comprueba si el ID aparece en la salida de --list (en cualquier parte)
world_exists() {
    local world_id="$1"
    local world_info
    world_info=$(get_world_info)
    if grep -Eq "${world_id}" <<< "$world_info"; then
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

    if [[ "$world_identifier" =~ ^[0-9a-fA-F]{32}$ ]]; then
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

    if [[ "$world_identifier" =~ ^[0-9a-fA-F]{32}$ ]]; then
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
