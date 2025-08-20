#!/bin/bash
set -e  # Finaliza inmediatamente si algún comando falla

# Verificación de privilegios de superusuario
if [ "$EUID" -ne 0 ]; then
    echo "Error: Este script requiere privilegios de administrador."
    echo "Ejecute con: sudo $0"
    exit 1
fi

# Configuración de variables
SERVER_URL="https://r2.theblockheads.xyz/server/blockheads_server171.tar.gz"
START_SCRIPT_URL="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/start.sh"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "================================================================"
echo "Instalador del Servidor The Blockheads para Linux"
echo "================================================================"

# Instalación de dependencias del sistema
echo "[1/5] Instalando paquetes requeridos..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget
} > /dev/null 2>&1

echo "[2/5] Descargando servidor..."
wget -q "$SERVER_URL" -O "$TEMP_FILE"

echo "[3/5] Extrayendo archivos..."
tar xzf "$TEMP_FILE" -C .
chmod +x "$SERVER_BINARY"

# Aplicación de parches de compatibilidad de bibliotecas
echo "[4/5] Configurando compatibilidad de bibliotecas..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY"
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY"
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY"
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY"
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY"
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY"
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY"

echo "[5/5] Configurando script de inicio..."
wget -q "$START_SCRIPT_URL" -O start.sh
chmod +x start.sh

# Limpieza de archivo temporal
rm -f "$TEMP_FILE"

# Verificación final
echo "================================================================"
echo "Instalación completada exitosamente"
echo "================================================================"
echo "Para iniciar el servidor ejecute: ./start.sh"
echo ""
echo "Configuración importante:"
echo "- Puerto predeterminado: 15151"
echo "- Asegúrese de configurar su firewall correctamente"
echo "- Los mundos se guardan en el directorio actual"
echo ""
echo "Verificando funcionamiento del ejecutable..."
if ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Estado: Ejecutable verificado correctamente"
else
    echo "Advertencia: El ejecutable podría tener problemas de compatibilidad"
fi
echo "================================================================"
