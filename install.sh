#!/bin/bash
set -e  # Exit immediately if any command fails

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Configuration variables
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
START_SCRIPT_URL="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main/start.sh"
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

echo "[5/5] Setting up start script..."
wget -q "$START_SCRIPT_URL" -O start.sh
chmod +x start.sh

# Set proper permissions for editing
chmod 644 start.sh  # Read/write for owner, read for others

# Clean up temporary file
rm -f "$TEMP_FILE"

# Final verification
echo "================================================================"
echo "Installation completed successfully"
echo "================================================================"
echo "To start the server run: ./start.sh"
echo ""
echo "Important configuration:"
echo "- Default port: 8080"
echo "- Ensure your firewall is properly configured"
echo "- Worlds are saved in the current directory"
echo ""
echo "Verifying executable..."
if ./blockheads_server171 --help > /dev/null 2>&1; then
    echo "Status: Executable verified successfully"
else
    echo "Warning: The executable might have compatibility issues"
fi
echo "================================================================"
