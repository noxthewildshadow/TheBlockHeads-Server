#!/usr/bin/env bash

# Blockheads Server Installer para Ubuntu Server 22.04
# Autor: Script mejorado para instalación automática

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directorio de instalación
INSTALL_DIR="$HOME/blockheads_server"
BINARY_NAME="blockheads_server171"

# Función para imprimir mensajes
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para instalar dependencias
install_dependencies() {
    print_status "Actualizando paquetes del sistema..."
    sudo apt update > /dev/null 2>&1
    
    print_status "Instalando dependencias necesarias..."
    
    # Lista de paquetes necesarios
    PACKAGES=(
        "curl"
        "tar"
        "patchelf"
        "libgnustep-base1.28"
        "libobjc4"
        "libgnutls30"
        "libgcrypt20"
        "libffi8"
        "libicu70"
        "libdispatch0"
    )
    
    # Instalar paquetes
    for package in "${PACKAGES[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            print_status "$package ya está instalado"
        else
            print_status "Instalando $package..."
            sudo apt install -y "$package" > /dev/null 2>&1
        fi
    done
    
    print_success "Dependencias instaladas correctamente"
}

# Función para descargar y configurar el servidor
setup_server() {
    print_status "Creando directorio de instalación..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    print_status "Descargando Blockheads Server..."
    curl -sL https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz | tar xvz > /dev/null 2>&1
    
    print_status "Aplicando parches de compatibilidad..."
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libffi.so.6 libffi.so.8 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 $BINARY_NAME > /dev/null 2>&1
    patchelf --replace-needed libdispatch.so libdispatch.so.0 $BINARY_NAME > /dev/null 2>&1
    
    # Hacer ejecutable el binario
    chmod +x $BINARY_NAME
    
    print_success "Servidor configurado correctamente"
}

# Función para crear el script de inicio
create_start_script() {
    print_status "Creando script de inicio..."
    
    cat > "$INSTALL_DIR/start_world.sh" << 'EOF'
#!/usr/bin/env bash

# Script para iniciar mundos de Blockheads Server
# Uso: ./start_world.sh WORLD_ID PORT [MAX_PLAYERS] [SAVE_DELAY]

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_usage() {
    echo "Uso: $0 WORLD_ID PORT [MAX_PLAYERS] [SAVE_DELAY]"
    echo ""
    echo "Argumentos:"
    echo "  WORLD_ID      - ID del mundo a cargar"
    echo "  PORT          - Puerto del servidor (ej: 15151)"
    echo "  MAX_PLAYERS   - Máximo de jugadores (opcional, default: 16)"
    echo "  SAVE_DELAY    - Retraso de guardado en segundos (opcional, default: 1)"
    echo ""
    echo "Ejemplos:"
    echo "  $0 mi_mundo 15151"
    echo "  $0 mi_mundo 15151 20"
    echo "  $0 mi_mundo 15151 20 5"
}

# Verificar argumentos mínimos
if [ $# -lt 2 ]; then
    print_error "Argumentos insuficientes"
    print_usage
    exit 1
fi

WORLD_ID="$1"
PORT="$2"
MAX_PLAYERS="${3:-16}"
SAVE_DELAY="${4:-1}"
BINARY="./blockheads_server171"

# Verificar que el binario existe
if [ ! -f "$BINARY" ]; then
    print_error "No se encontró el binario del servidor: $BINARY"
    print_error "Asegúrate de ejecutar este script desde el directorio de instalación"
    exit 1
fi

# Verificar que el mundo existe
print_status "Verificando que el mundo '$WORLD_ID' existe..."
if ! $BINARY --list | grep -q "$WORLD_ID"; then
    print_error "El mundo '$WORLD_ID' no existe"
    echo ""
    echo "Mundos disponibles:"
    $BINARY --list
    echo ""
    echo "Para crear un nuevo mundo, usa:"
    echo "  $BINARY --new NOMBRE_MUNDO --world_id $WORLD_ID --port $PORT"
    exit 1
fi

# Verificar que el puerto no esté en uso
if netstat -tuln | grep -q ":$PORT "; then
    print_error "El puerto $PORT ya está en uso"
    echo "Puertos en uso:"
    netstat -tuln | grep ":$PORT"
    exit 1
fi

print_success "Iniciando mundo '$WORLD_ID' en puerto $PORT..."
print_status "Configuración:"
print_status "  - Mundo: $WORLD_ID"
print_status "  - Puerto: $PORT"
print_status "  - Máximo jugadores: $MAX_PLAYERS"
print_status "  - Retraso guardado: ${SAVE_DELAY}s"
echo ""
print_status "Presiona Ctrl+C para detener el servidor"
echo ""

# Iniciar el servidor
exec $BINARY --load "$WORLD_ID" --port "$PORT" --max_players "$MAX_PLAYERS" --save_delay "$SAVE_DELAY"
EOF

    chmod +x "$INSTALL_DIR/start_world.sh"
    print_success "Script de inicio creado: $INSTALL_DIR/start_world.sh"
}

# Función para crear script de gestión de mundos
create_world_manager() {
    print_status "Creando script de gestión de mundos..."
    
    cat > "$INSTALL_DIR/world_manager.sh" << 'EOF'
#!/usr/bin/env bash

# Script para gestionar mundos de Blockheads Server

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BINARY="./blockheads_server171"

show_help() {
    echo "Gestor de Mundos de Blockheads Server"
    echo ""
    echo "Uso: $0 [COMANDO] [ARGUMENTOS]"
    echo ""
    echo "Comandos disponibles:"
    echo "  list                           - Listar todos los mundos"
    echo "  create NOMBRE [WORLD_ID] [OPTIONS] - Crear nuevo mundo"
    echo "  delete WORLD_ID                - Eliminar mundo"
    echo "  rename WORLD_ID NUEVO_NOMBRE   - Renombrar mundo"
    echo "  info WORLD_ID                  - Información del mundo"
    echo ""
    echo "Opciones para crear mundo:"
    echo "  --port PORT          - Puerto (default: 15151)"
    echo "  --max_players NUM    - Máximo jugadores (default: 16)"
    echo "  --world_width SIZE   - Tamaño mundo (1/16, 1/4, 1, 4, 16)"
    echo "  --expert-mode        - Modo experto"
    echo "  --owner OWNER        - Propietario del mundo"
    echo ""
    echo "Ejemplos:"
    echo "  $0 list"
    echo "  $0 create \"Mi Mundo\" mi_mundo_01 --port 15151"
    echo "  $0 delete mi_mundo_01"
}

case "$1" in
    "list"|"l")
        print_status "Mundos disponibles:"
        $BINARY --list
        ;;
    "create"|"c")
        if [ -z "$2" ]; then
            print_error "Nombre del mundo requerido"
            show_help
            exit 1
        fi
        
        WORLD_NAME="$2"
        WORLD_ID="$3"
        shift 3
        
        CMD="$BINARY --new \"$WORLD_NAME\""
        
        if [ ! -z "$WORLD_ID" ]; then
            CMD="$CMD --world_id \"$WORLD_ID\""
        fi
        
        # Procesar opciones adicionales
        while [ $# -gt 0 ]; do
            case "$1" in
                "--port")
                    CMD="$CMD --port $2"
                    shift 2
                    ;;
                "--max_players")
                    CMD="$CMD --max_players $2"
                    shift 2
                    ;;
                "--world_width")
                    CMD="$CMD --world_width $2"
                    shift 2
                    ;;
                "--expert-mode")
                    CMD="$CMD --expert-mode"
                    shift
                    ;;
                "--owner")
                    CMD="$CMD --owner \"$2\""
                    shift 2
                    ;;
                *)
                    print_error "Opción desconocida: $1"
                    exit 1
                    ;;
            esac
        done
        
        print_status "Creando mundo '$WORLD_NAME'..."
        eval $CMD
        print_success "Mundo creado exitosamente"
        ;;
    "delete"|"d")
        if [ -z "$2" ]; then
            print_error "ID del mundo requerido"
            exit 1
        fi
        
        print_status "Eliminando mundo '$2'..."
        $BINARY --delete "$2" --force
        print_success "Mundo eliminado"
        ;;
    "rename"|"r")
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "ID del mundo y nuevo nombre requeridos"
            exit 1
        fi
        
        print_status "Renombrando mundo '$2' a '$3'..."
        $BINARY --rename-from "$2" --rename-to "$3"
        print_success "Mundo renombrado"
        ;;
    "info"|"i")
        if [ -z "$2" ]; then
            print_error "ID del mundo requerido"
            exit 1
        fi
        
        print_status "Información del mundo '$2':"
        $BINARY --list | grep "$2" || print_error "Mundo no encontrado"
        ;;
    "help"|"h"|"")
        show_help
        ;;
    *)
        print_error "Comando desconocido: $1"
        show_help
        exit 1
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/world_manager.sh"
    print_success "Script de gestión creado: $INSTALL_DIR/world_manager.sh"
}

# Función para crear script de ejemplo
create_example_setup() {
    print_status "Creando script de ejemplo..."
    
    cat > "$INSTALL_DIR/example_setup.sh" << 'EOF'
#!/usr/bin/env bash

# Script de ejemplo para configurar un mundo de prueba

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

print_status "Creando mundo de ejemplo..."

# Crear mundo de ejemplo
./world_manager.sh create "Mundo de Ejemplo" ejemplo_01 --port 15151 --max_players 20

print_success "Mundo de ejemplo creado!"
echo ""
echo "Para iniciar el servidor:"
echo "  ./start_world.sh ejemplo_01 15151"
echo ""
echo "Para gestionar mundos:"
echo "  ./world_manager.sh list"
EOF

    chmod +x "$INSTALL_DIR/example_setup.sh"
    print_success "Script de ejemplo creado: $INSTALL_DIR/example_setup.sh"
}

# Función principal
main() {
    echo "=================================="
    echo "  Blockheads Server Installer"
    echo "  Ubuntu Server 22.04"
    echo "=================================="
    echo ""
    
    # Verificar sistema
    if [ ! -f /etc/os-release ] || ! grep -q "22.04" /etc/os-release; then
        print_warning "Este script está optimizado para Ubuntu Server 22.04"
        print_warning "Continuando de todos modos..."
    fi
    
    # Verificar permisos sudo
    if ! sudo -n true 2>/dev/null; then
        print_error "Este script requiere permisos sudo"
        print_error "Ejecuta: sudo -v"
        exit 1
    fi
    
    # Proceso de instalación
    install_dependencies
    setup_server
    create_start_script
    create_world_manager
    create_example_setup
    
    echo ""
    echo "=================================="
    print_success "INSTALACIÓN COMPLETADA"
    echo "=================================="
    echo ""
    print_status "Directorio de instalación: $INSTALL_DIR"
    print_status "Scripts disponibles:"
    echo "  - start_world.sh      : Iniciar mundos existentes"
    echo "  - world_manager.sh    : Gestionar mundos"
    echo "  - example_setup.sh    : Crear mundo de ejemplo"
    echo ""
    print_status "Próximos pasos:"
    echo "1. cd $INSTALL_DIR"
    echo "2. ./example_setup.sh                    # Crear mundo de ejemplo"
    echo "3. ./start_world.sh ejemplo_01 15151     # Iniciar servidor"
    echo ""
    print_status "O crear tu propio mundo:"
    echo "1. ./world_manager.sh create \"Mi Mundo\" mi_mundo --port 15151"
    echo "2. ./start_world.sh mi_mundo 15151"
    echo ""
    print_success "¡Disfruta tu servidor de Blockheads!"
}

# Ejecutar instalación
main "$@"
