#!/usr/bin/env bash

# Script de instalación para The Blockheads Server
# Ejecutar con: curl -sSL https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/main/Setup.sh | sudo bash

set -e  # Salir en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Verificar si estamos en Ubuntu 22.04
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "No se puede determinar la distribución de Linux"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "22.04" ]]; then
        print_warning "Este script está optimizado para Ubuntu 22.04. Puede que no funcione correctamente en otras distribuciones."
        if [[ -n "$FORCE_CONTINUE" ]]; then
            print_status "Continuando por variable FORCE_CONTINUE..."
        else
            read -p "¿Continuar de todos modos? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Instalar dependencias necesarias
install_dependencies() {
    print_status "Instalando dependencias del sistema..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl patchelf libgnustep-base1.28 libobjc4 libgnutls30 libgcrypt20 libffi8 libicu70 libdispatch0 > /dev/null 2>&1
}

# Configurar el directorio de mundos
setup_worlds_directory() {
    print_status "Configurando directorio de mundos..."
    
    # Crear directorio si no existe
    if [[ -n "$SUDO_USER" ]]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        USER_HOME="$HOME"
    fi
    
    # Crear ambos directorios para mayor compatibilidad
    WORLD_DIR="$USER_HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/Saves"
    mkdir -p "$WORLD_DIR"
    
    # Cambiar propietario si se ejecutó con sudo
    if [[ -n "$SUDO_USER" ]]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/GNUstep"
    fi
}

# Descargar y configurar el servidor
setup_server() {
    print_status "Creando directorio para el servidor..."
    mkdir -p /opt/blockheads-server
    cd /opt/blockheads-server

    print_status "Descargando el servidor de The Blockheads..."
    curl -sL https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz | tar xz -C ./ > /dev/null 2>&1

    # Verificar que el binario se descargó correctamente
    if [[ ! -f "blockheads_server171" ]]; then
        print_error "Error: El binario blockheads_server171 no se descargó correctamente"
        exit 1
    fi

    print_status "Aplicando parches al binario..."
    # Aplicar parches de forma no fatal
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171 > /dev/null 2>&1 || true
    patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171 > /dev/null 2>&1 || true

    # Hacer el binario ejecutable
    chmod +x blockheads_server171
    
    # Verificar que el binario existe y es ejecutable
    if [[ ! -f "blockheads_server171" ]]; then
        print_error "Error: El binario blockheads_server171 no existe"
        exit 1
    fi
    
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
    
    # Crear el script de gestión
    cat > /usr/local/bin/blockheads << 'EOF'
#!/usr/bin/env bash

# Configuración
SERVER_DIR="/opt/blockheads-server"
SERVER_BIN="$SERVER_DIR/blockheads_server171"

# Función para mostrar ayuda
show_help() {
    echo "Uso: blockheads [COMANDO] [OPCIONES]"
    echo ""
    echo "Comandos:"
    echo "  create <NOMBRE_MUNDO> [OPCIONES]  Crear un nuevo mundo"
    echo "  start <ID_MUNDO> [PUERTO]         Iniciar un mundo existente"
    echo "  list                              Listar todos los mundos"
    echo "  delete <ID_MUNDO>                 Eliminar un mundo"
    echo "  help                              Mostrar esta ayuda"
    echo ""
    echo "Opciones para crear:"
    echo "  -p, --port PORT                   Puerto del servidor (por defecto: 15151)"
    echo "  -m, --max-players MAX             Máximo de jugadores (por defecto: 16, máximo: 32)"
    echo "  -w, --world-width TAMAÑO          Tamaño del mundo (1/16, 1/4, 1, 4, 16)"
    echo "  -e, --expert-mode                 Habilitar modo experto"
}

# Función para obtener información de mundos
get_world_info() {
    cd "$SERVER_DIR"
    "$SERVER_BIN" --list
}

# Función para parsear la salida de --list y obtener ID y nombre
parse_world_list() {
    local world_info=$(get_world_info)
    echo "$world_info" | while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # El formato es: "NOMBRE" stored in directory named ID
            if [[ "$line" =~ \""(.*)\""\ stored\ in\ directory\ named\ ([0-9a-f]+)$ ]]; then
                local name="${BASH_REMATCH[1]}"
                local id="${BASH_REMATCH[2]}"
                echo "$id $name"
            fi
        fi
    done
}

# Función para obtener el ID de un mundo por nombre
get_world_id_by_name() {
    local world_name="$1"
    parse_world_list | while read -r id name; do
        if [[ "$name" == "$world_name" ]]; then
            echo "$id"
            return 0
        fi
    done
}

# Función para obtener el nombre de un mundo por ID
get_world_name_by_id() {
    local world_id="$1"
    parse_world_list | while read -r id name; do
        if [[ "$id" == "$world_id" ]]; then
            echo "$name"
            return 0
        fi
    done
}

# Función para verificar si un mundo existe por ID
world_exists_by_id() {
    local world_id="$1"
    parse_world_list | while read -r id name; do
        if [[ "$id" == "$world_id" ]]; then
            return 0
        fi
    done
    return 1
}

# Función para verificar si un mundo existe por nombre
world_exists_by_name() {
    local world_name="$1"
    parse_world_list | while read -r id name; do
        if [[ "$name" == "$world_name" ]]; then
            return 0
        fi
    done
    return 1
}

# Función para resolver un identificador (ID o nombre) a ID
resolve_world_identifier() {
    local identifier="$1"
    
    # Si es un ID válido (32 caracteres hexadecimales)
    if [[ "$identifier" =~ ^[0-9a-f]{32}$ ]]; then
        if world_exists_by_id "$identifier"; then
            echo "$identifier"
            return 0
        fi
    fi
    
    # Si es un nombre, buscar el ID
    local world_id=$(get_world_id_by_name "$identifier")
    if [[ -n "$world_id" ]]; then
        echo "$world_id"
        return 0
    fi
    
    return 1
}

# Función para crear un mundo
create_world() {
    local world_name="$1"
    shift
    local extra_args=""
    
    # Parsear argumentos adicionales
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port)
                extra_args="$extra_args --port $2"
                shift 2
                ;;
            -m|--max-players)
                extra_args="$extra_args --max_players $2"
                shift 2
                ;;
            -w|--world-width)
                extra_args="$extra_args --world_width $2"
                shift 2
                ;;
            -e|--expert-mode)
                extra_args="$extra_args --expert-mode"
                shift
                ;;
            *)
                echo "Opción desconocida: $1"
                exit 1
                ;;
        esac
    done
    
    # Crear el mundo
    cd "$SERVER_DIR"
    "$SERVER_BIN" --new "$world_name" $extra_args
    
    # Obtener el ID del mundo recién creado
    local world_id=$(get_world_id_by_name "$world_name")
    
    if [[ -n "$world_id" ]]; then
        echo "Mundo creado con éxito. ID: $world_id"
        echo "Para iniciarlo: blockheads start $world_id"
    else
        echo "Error: No se pudo determinar el ID del mundo creado."
        echo "Intenta listar los mundos con: blockheads list"
    fi
}

# Función para iniciar un mundo
start_world() {
    local world_identifier="$1"
    local port="${2:-15151}"
    local world_id
    
    # Resolver el identificador (puede ser ID o nombre)
    world_id=$(resolve_world_identifier "$world_identifier")
    if [[ $? -ne 0 ]] || [[ -z "$world_id" ]]; then
        echo "Error: No existe un mundo con identificador '$world_identifier'"
        echo "Lista de mundos disponibles:"
        list_worlds
        exit 1
    fi
    
    echo "Iniciando mundo ID: $world_id en puerto: $port"
    cd "$SERVER_DIR"
    "$SERVER_BIN" --load "$world_id" --port "$port" --no-exit
}

# Función para listar mundos
list_worlds() {
    cd "$SERVER_DIR"
    echo "Mundos disponibles:"
    "$SERVER_BIN" --list
}

# Función para eliminar un mundo
delete_world() {
    local world_identifier="$1"
    local world_id
    local reply
    
    # Resolver el identificador (puede ser ID o nombre)
    world_id=$(resolve_world_identifier "$world_identifier")
    if [[ $? -ne 0 ]] || [[ -z "$world_id" ]]; then
        echo "Error: No existe un mundo con identificador '$world_identifier'"
        echo "Lista de mundos disponibles:"
        list_worlds
        exit 1
    fi
    
    # Obtener el nombre del mundo para mostrar
    local world_name=$(get_world_name_by_id "$world_id")
    
    read -r -p "¿Estás seguro de que quieres eliminar el mundo '$world_name' (ID: $world_id)? (y/N): " reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    echo "Eliminando mundo '$world_name' (ID: $world_id)"
    cd "$SERVER_DIR"
    "$SERVER_BIN" --delete "$world_id" --force
}

# Main command processing
case "$1" in
    create)
        if [[ -z "$2" ]]; then
            echo "Error: Se requiere un nombre para el mundo"
            exit 1
        fi
        create_world "${@:2}"
        ;;
    start)
        if [[ -z "$2" ]]; then
            echo "Error: Se requiere el ID o nombre de un mundo"
            exit 1
        fi
        start_world "$2" "$3"
        ;;
    list)
        list_worlds
        ;;
    delete)
        if [[ -z "$2" ]]; then
            echo "Error: Se requiere el ID o nombre de un mundo"
            exit 1
        fi
        delete_world "$2"
        ;;
    help|*)
        show_help
        ;;
esac
EOF

    chmod +x /usr/local/bin/blockheads
}

# Crear script de desinstalación
create_uninstall_script() {
    print_status "Creando script de desinstalación..."
    cat > /usr/local/bin/blockheads-uninstall << 'EOF'
#!/usr/bin/env bash

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
    
    # Verificar si se está ejecutando como root
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
    echo "  blockheads start NOMBRE_MUNDO [PUERTO]"
    echo ""
    echo "Para listar todos los mundos:"
    echo "  blockheads list"
    echo ""
    echo "El servidor se ha instalado en: /opt/blockheads-server"
}

# Ejecutar función principal
main "$@"
