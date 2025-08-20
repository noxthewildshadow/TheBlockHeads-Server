#!/bin/bash
# =============================
# blockheads_install.sh
# Improved installer for The Blockheads server (blockheads_server171)
# - safer temp handling
# - checks for required tools and apt availability
# - writes a compatible start.sh matching the improved startup script below
# - performs libpatching when patchelf is available
# - preserves ownership for the original invoking user
# =============================

set -euo pipefail
trap 'rc=$?; cleanup; exit $rc' EXIT

cleanup() {
    [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR" || true
}

# Must be root to place files and install packages
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
# We'll write our own start.sh to guarantee compatibility with the improvements
# instead of downloading an external script.

TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/blockheads_server171.tar.gz"
WORK_DIR="$(pwd)"
SERVER_BINARY="$WORK_DIR/blockheads_server171"

echo "================================================================"
echo "The Blockheads Linux Server Installer (improved)"
echo "Target directory: $WORK_DIR"
echo "Installing as original user: $ORIGINAL_USER"
echo "================================================================"

# Helper: check command
_cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Install system dependencies (Debian/Ubuntu style) if apt-get available
if _cmd_exists apt-get; then
    echo "[1/5] Installing required packages (apt)..."
    # Ensure add-apt-repository will be available if needed
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y software-properties-common wget curl file patchelf >/dev/null
    # try to enable multiverse if possible
    if _cmd_exists add-apt-repository; then
        add-apt-repository multiverse -y >/dev/null 2>&1 || true
    fi
else
    echo "[1/5] Skipping automatic dependency install (apt-get not found)."
    echo "Please ensure the following are installed: wget or curl, tar, patchelf (optional), file."
fi

# Download server archive
echo "[2/5] Downloading server..."
if _cmd_exists wget; then
    wget -q "$SERVER_URL" -O "$TEMP_FILE"
elif _cmd_exists curl; then
    curl -sSL "$SERVER_URL" -o "$TEMP_FILE"
else
    echo "Error: neither wget nor curl is available to download the server archive."
    exit 1
fi

# Basic sanity check the file looks like a gzip tar
if ! file --mime-type "$TEMP_FILE" | grep -qE "(application/x-gzip|application/gzip|application/x-tar)"; then
    echo "Warning: downloaded file doesn't look like a gzip tarball. Continuing, but extraction may fail."
fi

# Extract
echo "[3/5] Extracting files to $WORK_DIR..."
tar xzf "$TEMP_FILE" -C "$WORK_DIR"

if [ ! -f "$SERVER_BINARY" ]; then
    echo "Error: expected server binary at $SERVER_BINARY but it was not found after extraction."
    exit 1
fi

# Make binary executable and create a safe backup copy
chmod +x "$SERVER_BINARY"
if [ ! -f "${SERVER_BINARY}.orig" ]; then
    cp -p "$SERVER_BINARY" "${SERVER_BINARY}.orig" || true
fi

# Apply library compatibility patches using patchelf if available
echo "[4/5] Configuring library compatibility (if patchelf available) ..."
if _cmd_exists patchelf; then
    # A list of replacements we want to try (old:new)
    replacements=(
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

    for pair in "${replacements[@]}"; do
        oldlib=${pair%%:*}
        newlib=${pair##*:}
        # Only try replace if binary actually needs the old library
        if patchelf --print-needed "$SERVER_BINARY" 2>/dev/null | grep -q "$oldlib"; then
            echo "Patching: $oldlib -> $newlib"
            if patchelf --replace-needed "$oldlib" "$newlib" "$SERVER_BINARY" 2>/dev/null; then
                echo "  Success"
            else
                echo "  Warning: patchelf failed for $oldlib -> $newlib (continuing)"
            fi
        fi
    done
else
    echo "patchelf not found; skipping binary library patching. (If you need to patch, install patchelf.)"
fi

# Write an improved start.sh that is compatible with this installer
echo "[5/5] Writing start.sh and setting permissions..."
cat > "$WORK_DIR/start.sh" <<'START_SH'
#!/usr/bin/env bash
# Improved start.sh for The Blockheads Server
set -euo pipefail

# Directory of the script (so it can be run from anywhere)
DIR="$(dirname "$(readlink -f "$0")")"

# Configurable values (edit these as needed)
world_id="83cad395edb8d0f1912fec89508d8a1d"
server_port=15151
restart_delay=1      # seconds to wait before restarting the server
max_restarts=0       # 0 means unlimited

# Log location will be placed in the invoking user's HOME by default
user_home="${HOME:-/root}"
log_dir="$user_home/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id"
log_file="$log_dir/console.log"
server_binary="$DIR/blockheads_server171"

# Create log directory if missing
mkdir -p "$log_dir"
chmod 755 "$log_dir" || true

# Ensure server binary exists and is executable
if [ ! -f "$server_binary" ]; then
    echo "Error: Cannot find server executable $server_binary"
    echo "Please run the installer in the same directory as the server binary."
    exit 1
fi
if [ ! -x "$server_binary" ]; then
    chmod +x "$server_binary" || true
fi

echo "Starting The Blockheads Server"
echo "World: $world_id"
echo "Port: $server_port"
echo "Log file: $log_file"
echo "Use Ctrl+C to stop the loop (server will be terminated gracefully)."

restart_count=0

# Trap signals to allow graceful shutdown of the loop
terminate_loop=false

shutdown_handler() {
    terminate_loop=true
}

trap shutdown_handler SIGINT SIGTERM

while true; do
    if [ "$max_restarts" -gt 0 ] && [ "$restart_count" -ge "$max_restarts" ]; then
        echo "Reached max restarts ($max_restarts). Exiting."
        break
    fi

    restart_count=$((restart_count + 1))
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] Starting server (restart #$restart_count)" | tee -a "$log_file"

    # Run server; append output to log. Also stream to console using tee
    (cd "$DIR" && ./blockheads_server171 -o "$world_id" -p "$server_port") 2>&1 | tee -a "$log_file"

    exit_code=${PIPESTATUS[0]:-0}
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] Server closed (exit code: $exit_code)" | tee -a "$log_file"

    if [ "$terminate_loop" = true ]; then
        echo "Shutdown requested, exiting loop." | tee -a "$log_file"
        break
    fi

    echo "Restarting in $restart_delay second(s)..." | tee -a "$log_file"
    sleep "$restart_delay"
done

echo "Server loop terminated."
START_SH

# Set ownership and permissions so the original user can run start.sh
chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$WORK_DIR/start.sh" "$SERVER_BINARY" || true
chmod 755 "$WORK_DIR/start.sh" "$SERVER_BINARY" || true

# Remove temp files
cleanup

# Final verification (run --help as original user if possible)
echo "================================================================"
if _cmd_exists sudo && id -u "$ORIGINAL_USER" >/dev/null 2>&1; then
    echo "Verifying executable by running '--help' as $ORIGINAL_USER..."
    if sudo -u "$ORIGINAL_USER" "$SERVER_BINARY" --help >/dev/null 2>&1; then
        echo "Status: Executable verified successfully"
    else
        echo "Warning: Executable may have compatibility issues (returned non-zero or produced output)."
    fi
else
    echo "To verify manually, run: $SERVER_BINARY --help"
fi

echo "Installation completed."
echo "Run the server with: $WORK_DIR/start.sh"
echo "Or run manually: cd $WORK_DIR && ./blockheads_server171 -o <world_id> -p <port>"
echo "================================================================"
