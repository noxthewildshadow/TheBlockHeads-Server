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

# Where to fetch helper scripts (raw files in the repo)
RAW_BASE="https://raw.githubusercontent.com/noxthewildshadow/TheBlockHeads-Server/refs/heads/main"
START_SCRIPT_URL="$RAW_BASE/start_server.sh"
BOT_SCRIPT_URL="$RAW_BASE/bot_server.sh"
STOP_SCRIPT_URL="$RAW_BASE/stop_server.sh"

echo "================================================================"
echo "The Blockheads Linux Server Installer (with external scripts fetch)"
echo "================================================================"

# Install system dependencies
echo "[1/8] Installing required packages..."
{
    add-apt-repository multiverse -y || true
    apt-get update -y
    apt-get install -y libgnustep-base1.28 libdispatch0 patchelf wget jq screen lsof
} > /dev/null 2>&1

# Download helper scripts from GitHub raw
echo "[2/8] Downloading helper scripts from GitHub..."
if ! wget -q -O start_server.sh "$START_SCRIPT_URL"; then
    echo "ERROR: Failed to download start_server.sh from GitHub."
    exit 1
fi
if ! wget -q -O bot_server.sh "$BOT_SCRIPT_URL"; then
    echo "ERROR: Failed to download bot_server.sh from GitHub."
    exit 1
fi
if ! wget -q -O stop_server.sh "$STOP_SCRIPT_URL"; then
    echo "ERROR: Failed to download stop_server.sh from GitHub."
    exit 1
fi

chmod +x start_server.sh bot_server.sh stop_server.sh

echo "[3/8] Downloading server archive..."
if ! wget -q "$SERVER_URL" -O "$TEMP_FILE"; then
    echo "ERROR: Failed to download server file."
    echo "Please check your internet connection and try again."
    exit 1
fi

echo "[4/8] Extracting files..."
EXTRACT_DIR="/tmp/blockheads_extract_$$"
mkdir -p "$EXTRACT_DIR"

if ! tar xzf "$TEMP_FILE" -C "$EXTRACT_DIR"; then
    echo "ERROR: Failed to extract server files."
    echo "The downloaded file may be corrupted."
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

# Move extracted files to current directory
cp -r "$EXTRACT_DIR"/* ./
rm -rf "$EXTRACT_DIR"

# Find or rename server binary
if [ ! -f "$SERVER_BINARY" ]; then
    echo "WARNING: $SERVER_BINARY not found. Searching for alternative binary names..."
    ALTERNATIVE_BINARY=$(find . -name "*blockheads*" -type f -executable | head -n 1)
    if [ -n "$ALTERNATIVE_BINARY" ]; then
        echo "Found alternative binary: $ALTERNATIVE_BINARY"
        mv "$ALTERNATIVE_BINARY" "blockheads_server171"
        SERVER_BINARY="blockheads_server171"
        echo "Renamed to: blockheads_server171"
    else
        echo "ERROR: Could not find the server binary."
        echo "Contents of the downloaded archive:"
        tar -tzf "$TEMP_FILE"
        exit 1
    fi
fi

chmod +x "$SERVER_BINARY"

echo "[5/8] Applying patchelf compatibility patches..."
patchelf --replace-needed libgnustep-base.so.1.24 libgnustep-base.so.1.28 "$SERVER_BINARY" || echo "Warning: libgnustep-base patch may have failed"
patchelf --replace-needed libobjc.so.4.6 libobjc.so.4 "$SERVER_BINARY" || echo "Warning: libobjc patch may have failed"
patchelf --replace-needed libgnutls.so.26 libgnutls.so.30 "$SERVER_BINARY" || echo "Warning: libgnutls patch may have failed"
patchelf --replace-needed libgcrypt.so.11 libgcrypt.so.20 "$SERVER_BINARY" || echo "Warning: libgcrypt patch may have failed"
patchelf --replace-needed libffi.so.6 libffi.so.8 "$SERVER_BINARY" || echo "Warning: libffi patch may have failed"
patchelf --replace-needed libicui18n.so.48 libicui18n.so.70 "$SERVER_BINARY" || echo "Warning: libicui18n patch may have failed"
patchelf --replace-needed libicuuc.so.48 libicuuc.so.70 "$SERVER_BINARY" || echo "Warning: libicuuc patch may have failed"
patchelf --replace-needed libicudata.so.48 libicudata.so.70 "$SERVER_BINARY" || echo "Warning: libicudata patch may have failed"
patchelf --replace-needed libdispatch.so libdispatch.so.0 "$SERVER_BINARY" || echo "Warning: libdispatch patch may have failed"

echo "[6/8] Set ownership and permissions for helper scripts"
chown "$ORIGINAL_USER:$ORIGINAL_USER" start_server.sh bot_server.sh stop_server.sh "$SERVER_BINARY" || true
chmod 755 start_server.sh bot_server.sh stop_server.sh "$SERVER_BINARY" || true

echo "[7/8] Create economy data file"
sudo -u "$ORIGINAL_USER" bash -c 'echo "{\"players\": {}, \"transactions\": []}" > economy_data.json' || true
chown "$ORIGINAL_USER:$ORIGINAL_USER" economy_data.json || true

# Clean up
rm -f "$TEMP_FILE"

echo "[8/8] Installation completed successfully"
echo ""
echo "IMPORTANT: First create a world manually with:"
echo "  ./blockheads_server171 -n"
echo ""
echo "Then start the server and bot with:"
echo "  ./start_server.sh start WORLD_ID PORT"
echo ""
echo "Example:"
echo "  ./start_server.sh start c1ce8d817c47daa51356cdd4ab64f032 12153"
echo ""
echo "Other commands:"
echo "  ./start_server.sh stop     - Stop server and bot"
echo "  ./start_server.sh status   - Show status"
echo "================================================================"
