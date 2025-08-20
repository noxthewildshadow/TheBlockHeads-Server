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
START_SCRIPT_URL="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/start.sh"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"
INSTALL_DIR="/opt/blockheads-server"

echo "================================================================"
echo "The Blockheads Linux Server Installer"
echo "================================================================"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Install system dependencies
echo "[1/5] Installing required packages..."
{
    apt-get update -y
    apt-get install -y software-properties-common
    add-apt-repository multiverse -y
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch-dev patchelf wget
} > /dev/null 2>&1

echo "[2/5] Downloading server..."
wget -q "$SERVER_URL" -O "$TEMP_FILE"

echo "[3/5] Extracting files..."
tar xzf "$TEMP_FILE" -C "$INSTALL_DIR"
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

echo "[5/5] Setting up start script..."
wget -q "$START_SCRIPT_URL" -O start.sh
sed -i "s|server_binary=\"./blockheads_server171\"|server_binary=\"$INSTALL_DIR/blockheads_server171\"|" start.sh

# Set proper ownership and permissions
echo "Setting proper file permissions..."
chown -R $ORIGINAL_USER:$ORIGINAL_USER "$INSTALL_DIR"
chmod 755 start.sh
chmod 755 "$SERVER_BINARY"

# Clean up temporary file
rm -f "$TEMP_FILE"

# Final verification
echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "Server installed in: $INSTALL_DIR"
echo "To start the server run: ./start.sh"
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
fi
echo "================================================================"
