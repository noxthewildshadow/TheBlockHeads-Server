#!/bin/bash

# =============================================================================
# Script de inicio del servidor The Blockheads
# Este script mantiene el servidor ejecutándose continuamente, reiniciando
# automáticamente si se cierra inesperadamente.
# =============================================================================

# Configuración del mundo y puerto
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151

# Directorio de logs (usando ~ para el home del usuario)
log_dir="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"

# Asegurar que el directorio de logs existe
mkdir -p "$log_dir"

# Contador de reinicios
restart_count=0

echo "Iniciando servidor The Blockheads"
echo "Mundo: $world_id"
echo "Puerto: $server_port"
echo "Registros en: $log_file"
echo "Presiona Ctrl+C para detener el servidor"
echo "----------------------------------------"

# Bucle principal de ejecución
while true; do
    # Incrementar contador de reinicios
    ((restart_count++))
    
    # Registrar inicio de sesión
    echo "$(date): Iniciando servidor (reinicio #$restart_count)" >> "$log_file"
    
    # Ejecutar servidor y capturar salida
    ./blockheads_server171 -o "$world_id" -p "$server_port" >> "$log_file" 2>&1
    
    # Registrar cierre inesperado
    exit_code=$?
    echo "$(date): Servidor cerrado inesperadamente (código: $exit_code)" >> "$log_file"
    
    # Esperar antes de reiniciar
    echo "$(date): Reiniciando en 1 segundo..." >> "$log_file"
    sleep 1
done
