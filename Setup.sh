#!/bin/bash

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script como root usando sudo."
    exit 1
fi

# Actualizar sistema e instalar dependencias
echo "Instalando dependencias..."
apt-get update
apt-get install -y curl patchelf libgnustep-base1.28 libobjc4 libgnutls30 libgcrypt20 libffi8 libicu70 libdispatch0

# Descargar y extraer el servidor
echo "Descargando servidor de The Blockheads..."
curl -sL https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz | tar xvz

# Aplicar parches de compatibilidad
echo "Aplicando parches de compatibilidad..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171
patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171
patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171
patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171

# Crear script de inicio
cat > start_world.sh << 'EOF'
#!/bin/bash

WORLD_ID=$1
PORT=${2:-15151}

if [ -z "$WORLD_ID" ]; then
    echo "Uso: $0 WORLD_ID [PUERTO]"
    exit 1
fi

./blockheads_server171 --load "$WORLD_ID" --port "$PORT" --no-exit
EOF

chmod +x start_world.sh

# Crear script de creación de mundos
cat > create_world.sh << 'EOF'
#!/bin/bash

WORLD_NAME=$1
WORLD_ID=$2
PORT=${3:-15151}

if [ -z "$WORLD_NAME" ] || [ -z "$WORLD_ID" ]; then
    echo "Uso: $0 NOMBRE_MUNDO ID_MUNDO [PUERTO]"
    exit 1
fi

./blockheads_server171 --new "$WORLD_NAME" --world_id "$WORLD_ID" --port "$PORT"
EOF

chmod +x create_world.sh

echo "Instalación completada."
echo ""
echo "Para crear un nuevo mundo:"
echo "./create_world.sh NOMBRE_MUNDO ID_MUNDO [PUERTO]"
echo ""
echo "Para iniciar un mundo existente:"
echo "./start_world.sh ID_MUNDO [PUERTO]"
