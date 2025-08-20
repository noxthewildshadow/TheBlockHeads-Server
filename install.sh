#!/bin/bash
set -e  # Exit immediately if any command fails

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Get the original user who invoked sudo
ORIGINAL_USER=${SUDO_USER:-$USER}

# Configuration variables
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"
INSTALL_DIR="/opt/blockheads-server"  # FIJADO: Directorio de instalación definido

echo "================================================================"
echo "The Blockheads Linux Server Installer"
echo "================================================================"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"  # FIJADO: Cambiamos al directorio de instalación

# Install system dependencies
echo "[1/5] Installing required packages..."
{
    apt-get update -y
    apt-get install -y software-properties-common  # FIJADO: Necesario para add-apt-repository
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget  # FIJADO: libdispatch0 en lugar de libdispatch-dev
} > /dev/null 2>&1

echo "[2/5] Downloading server..."
wget -q "$SERVER_URL" -O "$TEMP_FILE"

echo "[3/5] Extracting files..."
tar xzf "$TEMP_FILE" -C "$INSTALL_DIR"  # FIJADO: Especificamos directorio de extracción
chmod +x "$SERVER_BINARY"

# Apply library compatibility patches
echo "[4/5] Configuring library compatibility..."
# Check if each library exists before patching
libs_to_patch=(
    "libgnustep-base.so.1.24:libgnustep-base.so.1.28"
    "libobjc.so.4.6:libobjc.so.4"
    "libgnutls.so.26:libgnutls.so.30"
    "libgcrypt.so.11:libgcrypt.so.20"
    "libffi.so.6:libffi.so.8"
    "libicui18n.so.48:libicui18n.so.70"
    "libicuuc.so.48:libicuuc.so.70"
    "libicudata.so.48:libicudata.so.70"
    "libdispatch.so:libdispatch.so.0"
)

for lib_pair in "${libs_to_patch[@]}"; do
    old_lib="${lib_pair%%:*}"
    new_lib="${lib_pair#*:}"
    if ldd "$SERVER_BINARY" | grep -q "$old_lib"; then
        patchelf --replace-needed "$old_lib" "$new_lib" "$SERVER_BINARY"
    fi
done

echo "[5/5] Creating start script..."
# Create the start script directly instead of downloading it
cat > start.sh << 'EOF'
#!/bin/bash

# =============================================================================
# The Blockheads Server Startup Script
# This script keeps the server running continuously, restarting automatically
# if it closes unexpectedly.
# =============================================================================

# Configurable settings - user can adjust these values
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151

# Directories and paths
user_home="$HOME"
log_dir="$user_home/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="/opt/blockheads-server/blockheads_server171"  # FIJADO: Ruta absoluta

# Check and create log directory if it doesn't exist
if [ ! -d "$log_dir" ]; then
    echo "Creating log directory: $log_dir"
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
    chown "$USER:$USER" "$log_dir"  # FIJADO: Establecer propiedad correcta
fi

# Verify the server executable exists
if [ ! -f "$server_binary" ]; then
    echo "Error: Cannot find server executable $server_binary"
    echo "Please run the installation script first."
    exit 1
fi

# Ensure execute permissions on the binary
if [ ! -x "$server_binary" ]; then
    echo "Setting execute permissions on server binary..."
    chmod +x "$server_binary"
fi

echo "Starting The Blockheads Server"
echo "World: $world_id"
echo "Port: $server_port"
echo "Logs: $log_file"
echo "Use Ctrl+C to stop the server"
echo "----------------------------------------"

# Restart counter
restart_count=0

# Cleanup function for graceful shutdown
cleanup() {
    echo ""
    echo "Shutting down server..."
    kill -TERM $server_pid 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main execution loop
while true; do
    restart_count=$((restart_count + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] Starting server (restart #$restart_count)" >> "$log_file"
    
    # Run server and capture output
    $server_binary -o "$world_id" -p "$server_port" >> "$log_file" 2>&1 &
    server_pid=$!
    
    wait $server_pid
    
    # Log exit and prepare for restart
    exit_code=$?
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Server closed (exit code: $exit_code), restarting in 3s..." >> "$log_file"
    
    sleep 3
done
EOF

# Set proper ownership and permissions
echo "Setting proper file permissions..."
chown -R $ORIGINAL_USER:$ORIGINAL_USER "$INSTALL_DIR"  # FIJADO: Propiedad recursiva
chmod 755 start.sh
chmod 755 "$SERVER_BINARY"

# Clean up temporary file
rm -f "$TEMP_FILE"

# Final verification
echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "Server installed in: $INSTALL_DIR"
echo "To start the server: cd $INSTALL_DIR && ./start.sh"  # FIJADO: Instrucción mejorada
echo ""
echo "Important configuration:"
echo "- Default port: 15151"
echo "- Ensure your firewall is properly configured"
echo "- Worlds are saved in: $INSTALL_DIR"
echo ""
echo "Verifying executable..."
if ldd "$SERVER_BINARY" > /dev/null 2>&1; then
    echo "Status: Libraries verified successfully"
else
    echo "Warning: Some library dependencies may be missing"
    echo "Run 'ldd $SERVER_BINARY' to see missing dependencies"
fi
echo "================================================================"
