#!/usr/bin/env bash

#
# Script de instalación para The Blockheads Server en Ubuntu 22.04 LTS
#
# Este script se encarga de:
# 1. Instalar las dependencias de librerías necesarias de forma silenciosa.
# 2. Descargar y extraer el binario del servidor.
# 3. Parchear el binario para que sea compatible con las librerías de Ubuntu 22.04.
# 4. Crear un script llamado 'start_world.sh' para facilitar el inicio de mundos.
#

# --- PARÁMETROS DE CONFIGURACIÓN ---
# Puedes cambiar esta URL si se actualiza o la guardas en otro lugar
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"

# --- PROCESO DE INSTALACIÓN ---

echo "Iniciando la instalación de The Blockheads Server..."
echo "Esto puede tardar unos minutos, por favor, espera..."

# 1. Instalar dependencias necesarias de forma silenciosa
# Se utilizan flags para evitar preguntas y reducir la salida en pantalla.
sudo apt-get update -qq > /dev/null
sudo apt-get install -y --no-install-recommends \
    curl \
    tar \
    patchelf \
    libgnustep-base1.28 \
    libobjc-9-dev \
    libgnutls30 \
    libgcrypt20 \
    libffi-dev \
    libicu70 \
    libdispatch0 > /dev/null

if [ $? -ne 0 ]; then
    echo "Error: No se pudieron instalar todas las dependencias. Verifica tu conexión a internet o los repositorios de APT."
    exit 1
fi

echo "Dependencias instaladas exitosamente."

# 2. Descargar, extraer y limpiar
echo "Descargando el binario del servidor..."
curl -sL "${SERVER_URL}" | tar xvz
if [ $? -ne 0 ]; then
    echo "Error: Falló la descarga o extracción del archivo del servidor."
    exit 1
fi
echo "Binario descargado y extraído."

# 3. Parchear el binario
echo "Parcheando el binario para compatibilidad con Ubuntu 22.04..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 blockheads_server171
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 blockheads_server171
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 blockheads_server171
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 blockheads_server171
patchelf --replace-needed libffi.so.6 libffi.so.8 blockheads_server171
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 blockheads_server171
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 blockheads_server171
patchelf --replace-needed libicudata.so.48 libicudata.so.70 blockheads_server171
patchelf --replace-needed libdispatch.so libdispatch.so.0 blockheads_server171
echo "Parche completado."

# 4. Crear el script de inicio
echo "Creando el script 'start_world.sh' para un fácil inicio de mundos..."
cat << 'EOF' > start_world.sh
#!/usr/bin/env bash

#
# Script para iniciar un mundo de The Blockheads Server.
# Uso: ./start_world.sh <WORLD_ID> [PORT]
# Ejemplo: ./start_world.sh 12345 15151
#

# Verificar el número de argumentos
if [ -z "$1" ]; then
    echo "Uso: ./start_world.sh <WORLD_ID> [PORT]"
    exit 1
fi

WORLD_ID="$1"
PORT="${2:-15151}"  # Si no se especifica un puerto, usa 15151 por defecto

# Verificar si el binario existe
if [ ! -f "blockheads_server171" ]; then
    echo "Error: No se encontró el binario 'blockheads_server171' en este directorio."
    exit 1
fi

echo "Iniciando mundo con ID: $WORLD_ID en el puerto: $PORT..."
./blockheads_server171 --load "$WORLD_ID" --port "$PORT" --no-exit

EOF

chmod +x start_world.sh
chmod +x blockheads_server171

# 5. Mensaje final
echo "---"
echo "¡Instalación completada con éxito!"
echo ""
echo "Para crear un nuevo mundo, usa el siguiente comando:"
echo "./blockheads_server171 --new NOMBRE_MUNDO --port PUERTO --expert-mode"
echo ""
echo "Cuando tengas el ID de tu mundo, puedes iniciarlo fácilmente con:"
echo "./start_world.sh <ID_MUNDO> [PUERTO]"
echo ""
echo "Por ejemplo:"
echo "./start_world.sh 12345 15151"
echo ""
echo "¡Disfruta tu servidor!"
