#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Get the original user who invoked sudo
ORIGINAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

# Configuration variables
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

echo "================================================================"
echo "The Blockheads Linux Server Installer"
echo "================================================================"

# Install system dependencies
echo "[1/5] Installing required packages..."
{
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget
} > /dev/null 2>&1

echo "[2/5] Downloading server..."
wget -q "$SERVER_URL" -O "$TEMP_FILE"

echo "[3/5] Extracting files..."
tar xzf "$TEMP_FILE" -C .
chmod +x "$SERVER_BINARY"

# Apply library compatibility patches
echo "[4/5] Configuring library compatibility..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY"
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY"
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY"
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY"
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY"
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY"
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY"
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY"

echo "[5/5] Creating start script..."
cat > start.sh << EOF
#!/bin/bash

# Configurable settings
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151

# Directories and paths
log_dir="\$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/\$world_id"
log_file="\$log_dir/console.log"
server_binary="./blockheads_server171"

# Check and create log directory
if [ ! -d "\$log_dir" ]; then
    mkdir -p "\$log_dir"
    chmod 755 "\$log_dir"
fi

# Verify the server executable exists
if [ ! -f "\$server_binary" ]; then
    echo "Error: Cannot find server executable \$server_binary"
    exit 1
fi

# Ensure execute permissions
if [ ! -x "\$server_binary" ]; then
    chmod +x "\$server_binary"
fi

echo "Starting The Blockheads Server"
echo "World: \$world_id"
echo "Port: \$server_port"
echo "Logs: \$log_file"
echo "Use Ctrl+C to stop the server"
echo "----------------------------------------"

# Function to clean up on exit
cleanup() {
    echo ""
    echo "Server stopped. Logs saved to: \$log_file"
    exit 0
}

trap cleanup INT TERM

restart_count=0
while true; do
    restart_count=\$((restart_count + 1))
    timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    echo "[\$timestamp] Starting server (restart #\$restart_count)" | tee -a "\$log_file"
    
    # Run server with real-time log output
    \$server_binary -o "\$world_id" -p "\$server_port" 2>&1 | tee -a "\$log_file"
    
    exit_code=\${PIPESTATUS[0]}
    timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    echo "[\$timestamp] Server closed (exit code: \$exit_code), restarting in 3s..." | tee -a "\$log_file"
    sleep 3
done
EOF

# Set proper ownership and permissions
chown "$ORIGINAL_USER:$ORIGINAL_USER" start.sh "$SERVER_BINARY"
chmod 755 start.sh "$SERVER_BINARY"

# Clean up
rm -f "$TEMP_FILE"

echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "To use and see commands ./blockheads_server171 --help"
echo "To start the server run: ./start.sh"
echo ""
echo "Important configuration:"
echo "- Default port: 15151"
echo "- Ensure your firewall is properly configured"
echo "- Worlds are saved in the current directory"
echo ""
echo "Verifying executable..."
if sudo -u "$ORIGINAL_USER" ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Status: Executable verified successfully"
else
    echo "Warning: The executable might have compatibility issues"
fi
echo "================================================================"
