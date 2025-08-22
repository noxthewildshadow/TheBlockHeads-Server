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
        read -p "¿Continuar de todos modos? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Instalar dependencias necesarias
install_dependencies() {
    print_status "Instalando dependencias del sistema..."
    apt update
    apt install -y curl patchelf libgnustep-base1.28 libobjc4 libgnutls30 libgcrypt20 libffi8 libicu70 libdispatch0
}

# Descargar y configurar el servidor
setup_server() {
    print_status "Creando directorio para el servidor..."
    mkdir -p /opt/blockheads-server
    cd /opt/blockheads-server

    print_status "Descargando el servidor de The Blockheads..."
    curl -sL https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz | tar xz -C ./

    print_status "Aplicando parches al binario..."
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171
    patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171
    patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171

    # Hacer el binario ejecutable
    chmod +x blockheads_server171
}

# Crear script de gestión de mundos
create_management_script() {
    print_status "Creando script de gestión de mundos..."
    cat > /usr/local/bin/blockheads << 'EOF'
#!/usr/bin/env bash

# Configuración
SERVER_DIR="/opt/blockheads-server"
SERVER_BIN="$SERVER_DIR/blockheads_server171"
WORLDS_DIR="$SERVER_DIR/Worlds"

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
    echo "  -o, --owner PROPIETARIO           Establecer propietario del mundo"
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
            -o|--owner)
                extra_args="$extra_args --owner $2"
                shift 2
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
    local world_id=$("$SERVER_BIN" --list | grep "$world_name" | awk '{print $1}')
    
    if [[ -n "$world_id" ]]; then
        echo "Mundo creado con éxito. ID: $world_id"
        echo "Para iniciarlo: blockheads start $world_id"
    else
        echo "Error: No se pudo determinar el ID del mundo creado."
    fi
}

# Función para iniciar un mundo
start_world() {
    local world_id="$1"
    local port="${2:-15151}"
    
    # Verificar que el mundo existe
    cd "$SERVER_DIR"
    if ! "$SERVER_BIN" --list | grep -q "^$world_id"; then
        echo "Error: No existe un mundo con ID $world_id"
        exit 1
    fi
    
    echo "Iniciando mundo ID: $world_id en puerto: $port"
    "$SERVER_BIN" --load "$world_id" --port "$port" --no-exit
}

# Función para listar mundos
list_worlds() {
    cd "$SERVER_DIR"
    "$SERVER_BIN" --list
}

# Función para eliminar un mundo
delete_world() {
    local world_id="$1"
    
    # Verificar que el mundo existe
    cd "$SERVER_DIR"
    if ! "$SERVER_BIN" --list | grep -q "^$world_id"; then
        echo "Error: No existe un mundo con ID $world_id"
        exit 1
    fi
    
    read -p "¿Estás seguro de que quieres eliminar el mundo ID: $world_id? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    echo "Eliminando mundo ID: $world_id"
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
            echo "Error: Se requiere el ID de un mundo"
            exit 1
        fi
        start_world "$2" "$3"
        ;;
    list)
        list_worlds
        ;;
    delete)
        if [[ -z "$2" ]]; then
            echo "Error: Se requiere el ID de un mundo"
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
    echo ""
    echo "Para listar todos los mundos:"
    echo "  blockheads list"
    echo ""
    echo "El servidor se ha instalado en: /opt/blockheads-server"
}

# Ejecutar función principal
main "$@"
