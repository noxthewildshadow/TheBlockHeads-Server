#!/usr/bin/env bash

# Script de instalación y configuración automática
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INSTALL_DIR"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Verificar dependencias del sistema
check_dependencies() {
    local deps=("curl" "tar" "patchelf" "ldconfig")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        print_warning "Instalando dependencias faltantes: ${missing[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    fi
}

# Descargar y preparar el servidor
setup_server() {
    if [ ! -f "blockheads_server171" ]; then
        print_status "Descargando servidor de The Blockheads..."
        curl -sL https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz | tar xvz
    fi

    if [ ! -x "blockheads_server171" ]; then
        chmod +x blockheads_server171
    fi

    # Parchear librerías
    print_status "Aplicando parches de compatibilidad..."
    patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171 2>/dev/null
    patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171 2>/dev/null
    patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171 2>/dev/null
    patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171 2>/dev/null
    patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171 2>/dev/null
    patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171 2>/dev/null
    patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171 2>/dev/null
    patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171 2>/dev/null
    patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171 2>/dev/null
}

# Crear script de inicio
create_start_script() {
    cat > start_world.sh << 'EOF'
#!/usr/bin/env bash

WORLD_ID="$1"
PORT="${2:-15151}"

if [ -z "$WORLD_ID" ]; then
    echo "Uso: $0 WORLD_ID [PUERTO]"
    echo "Puerto predeterminado: 15151"
    exit 1
fi

# Verificar si el mundo existe
if ! ./blockheads_server171 --list | grep -q "[[:space:]]$WORLD_ID:"; then
    echo "Creando nuevo mundo con ID: $WORLD_ID"
    ./blockheads_server171 --new "Mundo_$WORLD_ID" --world_id "$WORLD_ID" --port "$PORT"
else
    echo "Cargando mundo existente: $WORLD_ID"
    ./blockheads_server171 --load "$WORLD_ID" --port "$PORT"
fi
EOF

    chmod +x start_world.sh
    print_status "Script de inicio creado: start_world.sh"
}

# Función principal
main() {
    print_status "Iniciando instalación automática..."
    
    check_dependencies
    setup_server
    create_start_script

    print_status "Instalación completada!"
    echo ""
    print_warning "Para iniciar el servidor:"
    echo "  ./start_world.sh <ID_MUNDO> [PUERTO]"
    echo ""
    print_warning "Para listar mundos existentes:"
    echo "  ./blockheads_server171 --list"
}

# Ejecutar instalación
main "$@"
