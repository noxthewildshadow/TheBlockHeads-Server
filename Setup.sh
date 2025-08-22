#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Original user (who invoked sudo)
ORIGINAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

# Installation directory in user's home
INSTALL_DIR="$USER_HOME/TheBlockheadsServer"
mkdir -p "$INSTALL_DIR"
chown "$ORIGINAL_USER:$ORIGINAL_USER" "$INSTALL_DIR"

# Configuration variables
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="/tmp/blockheads_server171.tar.gz"
SERVER_BINARY="blockheads_server171"

# Where to fetch helper scripts (raw files in the repo)
RAW_BASE="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main"
START_SCRIPT_URL="$RAW_BASE/start_server.sh"
BOT_SCRIPT_URL="$RAW_BASE/bot_server.sh"
STOP_SCRIPT_URL="$RAW_BASE/stop_server.sh"

echo "================================================================"
echo "The Blockheads Linux Server Installer (downloads helper scripts & organizes files in $INSTALL_DIR)"
echo "================================================================"

# Install system packages
echo "[1/8] Installing required packages..."
{
    add-apt-repository multiverse -y || true
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen lsof
} > /dev/null 2>&1 || true

# Download helper scripts from GitHub raw into install dir
echo "[2/8] Downloading helper scripts from GitHub into $INSTALL_DIR ..."
wget -q -O "$INSTALL_DIR/start_server.sh" "$START_SCRIPT_URL" || { echo "ERROR: cannot download start_server.sh"; exit 1; }
wget -q -O "$INSTALL_DIR/bot_server.sh" "$BOT_SCRIPT_URL" || { echo "ERROR: cannot download bot_server.sh"; exit 1; }
wget -q -O "$INSTALL_DIR/stop_server.sh" "$STOP_SCRIPT_URL" || { echo "ERROR: cannot download stop_server.sh"; exit 1; }

# Ensure scripts are executable
chmod +x "$INSTALL_DIR/start_server.sh" "$INSTALL_DIR/bot_server.sh" "$INSTALL_DIR/stop_server.sh"

echo "[3/8] Downloading server archive..."
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Failed to download server file."
    exit 1
fi

echo "[4/8] Extracting server archive into $INSTALL_DIR ..."
EXTRACT_DIR="/tmp/blockheads_extract_$$"
mkdir -p "$EXTRACT_DIR"
tar xzf "$TEMP_FILE" -C "$EXTRACT_DIR" || { echo "ERROR: extracting archive"; rm -rf "$EXTRACT_DIR"; exit 1; }

# Move extracted files to install dir
cp -r "$EXTRACT_DIR"/* "$INSTALL_DIR"/
rm -rf "$EXTRACT_DIR"

# Ensure server binary exists; try to find and rename if necessary
cd "$INSTALL_DIR" || exit 1
if [ ! -f "$SERVER_BINARY" ]; then
    ALTERNATIVE_BINARY=$(find . -maxdepth 2 -type f -executable -iname "*blockheads*" | head -n 1)
    if [ -n "$ALTERNATIVE_BINARY" ]; then
        mv "$ALTERNATIVE_BINARY" "$SERVER_BINARY"
    else
        echo "ERROR: Server binary not found in archive."
        ls -la
        exit 1
    fi
fi

chmod +x "$SERVER_BINARY"

echo "[5/8] Applying patchelf compatibility patches (best-effort)..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY" || true
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY" || true
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY" || true
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY" || true
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY" || true
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY" || true
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY" || true
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY" || true
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY" || true

echo "[6/8] Create economy data file and set ownership..."
if [ ! -f "economy_data.json" ]; then
    echo '{"players": {}, "transactions": []}' > economy_data.json
fi
chown "$ORIGINAL_USER:$ORIGINAL_USER" "$INSTALL_DIR" -R || true
chmod 755 "$INSTALL_DIR"/*.sh "$INSTALL_DIR/$SERVER_BINARY" || true

# Clean up
rm -f "$TEMP_FILE"

echo "[7/8] Finished files placement in $INSTALL_DIR"
echo "[8/8] Installation completed successfully"
echo ""
echo "IMPORTANT: cd into $INSTALL_DIR as $ORIGINAL_USER to create world & start server."
echo "Example:"
echo "  sudo -u $ORIGINAL_USER bash -c 'cd $INSTALL_DIR && ./blockheads_server171 -n'"
echo "  sudo -u $ORIGINAL_USER bash -c 'cd $INSTALL_DIR && ./start_server.sh start <WORLD_ID> 12153'"
echo "================================================================"
