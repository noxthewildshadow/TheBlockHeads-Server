#!/bin/bash
# =============================
# Blockheads Interactive Installer (English)
# This installer will:
#  - download and extract the Blockheads tarball
#  - create a start.sh matching your choices
#  - optionally create a systemd service
# The script uses dialog/whiptail if available, otherwise falls back to interactive prompts.
# =============================

set -euo pipefail
trap 'rc=$?; cleanup; exit $rc' EXIT

cleanup() {
    [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR" || true
}

# Helper: check for command
_cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# UI helpers: use dialog if present, else whiptail, else fallback to read
DIALOG_CMD=""
if _cmd_exists dialog; then
    DIALOG_CMD="dialog"
elif _cmd_exists whiptail; then
    DIALOG_CMD="whiptail"
else
    DIALOG_CMD=""
fi

ui_input() {
    # ui_input "Title" "Prompt" "default"
    local title="$1" prompt="$2" default="$3"
    if [ -n "$DIALOG_CMD" ]; then
        if [ "$DIALOG_CMD" = "dialog" ]; then
            result=$(mktemp)
            dialog --backtitle "Blockheads Installer" --ok-label "OK" --inputbox "$prompt" 10 60 "$default" 2>"$result" || true
            cat "$result"; rm -f "$result"
        else
            whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3 || true
        fi
    else
        read -rp "$prompt [$default]: " result
        result=${result:-$default}
        echo "$result"
    fi
}

ui_yesno() {
    # ui_yesno "Title" "Question" (returns 0 for yes, 1 for no)
    local title="$1" question="$2"
    if [ -n "$DIALOG_CMD" ]; then
        if [ "$DIALOG_CMD" = "dialog" ]; then
            dialog --backtitle "Blockheads Installer" --yes-label "Yes" --no-label "No" --yesno "$question" 8 60
            return $?
        else
            whiptail --title "$title" --yesno "$question" 8 60
            return $?
        fi
    else
        while true; do
            read -rp "$question (y/n): " yn
            case "$yn" in
                [Yy]*) return 0 ;; 
                [Nn]*) return 1 ;; 
                *) echo "Please answer y or n.";;
            esac
        done
    fi
}

# Ensure script runs as root because we'll install packages or write system files
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This installer needs root privileges. Please run with sudo."
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-$USER}
TEMP_DIR=$(mktemp -d)
WORK_DIR="$(pwd)"
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TEMP_FILE="$TEMP_DIR/blockheads_server171.tar.gz"

# Interactive flow: ask user for options
if [ -n "$DIALOG_CMD" ]; then
    if [ "$DIALOG_CMD" = "dialog" ]; then
        dialog --backtitle "Blockheads Installer" --title "Welcome" --msgbox "Welcome to the interactive installer for The Blockheads server.

It is recommended to run this script in the folder where you want the server files (for example: ~/blockheads-server).

Press OK to continue." 12 70
    else
        whiptail --title "Welcome" --msgbox "Welcome to the interactive installer for The Blockheads server.

It is recommended to run this script in the folder where you want the server files (for example: ~/blockheads-server).

Press OK to continue." 12 70
    fi
fi

# Default values
DEFAULT_INSTALL_DIR="$WORK_DIR"
default_world_id="83cad395edb8d0f1912fec89508d8a1d"
default_port=15151

install_dir=$(ui_input "Install directory" "Installation directory (absolute or relative path). The archive will be extracted here:" "$DEFAULT_INSTALL_DIR")
# Expand and normalize path
if [ -d "$install_dir" ]; then
    install_dir="$(cd "$install_dir" && pwd)"
else
    # Try to create parent and get absolute
    mkdir -p "$install_dir" 2>/dev/null || true
    install_dir="$(cd "$install_dir" 2>/dev/null && pwd || echo "$install_dir")"
fi

world_id=$(ui_input "World ID" "World ID (unique identifier for saves). You can keep the default:" "$default_world_id")

server_port=$(ui_input "Server port" "Server port (15151 is default):" "$default_port")
# Validate port
if ! echo "$server_port" | grep -Eq '^[0-9]+$' || [ "$server_port" -lt 1 ] || [ "$server_port" -gt 65535 ]; then
    echo "Invalid port: $server_port. Using 15151.";
    server_port=15151
fi

want_systemd=false
if ui_yesno "Service" "Do you want the installer to create a systemd service so the server runs in background and starts on boot?"; then
    want_systemd=true
fi

use_patchelf=false
if ui_yesno "Patchelf" "Do you want the installer to attempt binary compatibility patches using patchelf (requires patchelf) ?"; then
    use_patchelf=true
fi

# Confirm
if ! ui_yesno "Confirm" "Install server in: $install_dir
World ID: $world_id
Port: $server_port
Create systemd service: $want_systemd
Apply patchelf patches: $use_patchelf

Continue?"; then
    echo "Installation cancelled."; exit 0
fi

# Prepare install directory
mkdir -p "$install_dir"
chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$install_dir" || true
cd "$install_dir"

# Install recommended packages if apt-get present
if _cmd_exists apt-get; then
    echo "Installing required packages (if missing)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y wget curl tar file >/dev/null
    if [ "$use_patchelf" = true ]; then
        apt-get install -y patchelf >/dev/null
    fi
else
    echo "apt-get not found. Please ensure wget/curl/tar (and patchelf if requested) are installed manually."
fi

# Download archive
echo "Downloading server archive from: $SERVER_URL"
if _cmd_exists wget; then
    wget -q "$SERVER_URL" -O "$TEMP_FILE"
elif _cmd_exists curl; then
    curl -sSL "$SERVER_URL" -o "$TEMP_FILE"
else
    echo "Error: neither wget nor curl is available."; exit 1
fi

# Extract archive
echo "Extracting archive into: $install_dir"
if ! tar xzf "$TEMP_FILE" -C "$install_dir"; then
    echo "Extraction failed. Please check the downloaded tarball."; exit 1
fi

# Verify binary
server_binary="$install_dir/blockheads_server171"
if [ ! -f "$server_binary" ]; then
    echo "Error: blockheads_server171 binary was not found in the extracted archive."; exit 1
fi
chmod +x "$server_binary"
[ ! -f "${server_binary}.orig" ] && cp -p "$server_binary" "${server_binary}.orig" || true

# Attempt patchelf replacements if requested
if [ "$use_patchelf" = true ]; then
    if _cmd_exists patchelf; then
        echo "Attempting to patch runtime library dependencies using patchelf..."
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
            if patchelf --print-needed "$server_binary" 2>/dev/null | grep -q "$oldlib"; then
                echo "Patching $oldlib -> $newlib"
                if ! patchelf --replace-needed "$oldlib" "$newlib" "$server_binary" 2>/dev/null; then
                    echo "Warning: patchelf failed for $oldlib -> $newlib (continuing)"
                fi
            fi
        done
    else
        echo "patchelf not found. Skipping binary patch step."
    fi
fi

# Create start.sh
cat > "$install_dir/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DIR="\$(dirname "\$(readlink -f "$0")")"
world_id="$world_id"
server_port=$server_port
log_dir="\$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/\$world_id"
log_file="\$log_dir/console.log"
server_binary="\$DIR/blockheads_server171"
restart_delay=1
max_restarts=0
mkdir -p "\$log_dir"; chmod 755 "\$log_dir" || true
if [ ! -f "\$server_binary" ]; then
echo "Error: cannot find \$server_binary"; exit 1; fi
if [ ! -x "\$server_binary" ]; then chmod +x "\$server_binary" || true; fi
restart_count=0
terminate_loop=false
trap 'terminate_loop=true' SIGINT SIGTERM
while true; do
    if [ "$max_restarts" -gt 0 ] && [ "$restart_count" -ge "$max_restarts" ]; then
        echo "Reached max restarts, exiting."; break
    fi
    restart_count=\$((restart_count+1))
    ts="\$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[\$ts] Starting server (restart #\$restart_count)" | tee -a "\$log_file"
    (cd "\$DIR" && ./blockheads_server171 -o "\$world_id" -p "\$server_port") 2>&1 | tee -a "\$log_file"
    exit_code=\${PIPESTATUS[0]:-0}
    ts="\$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[\$ts] Server closed (exit code: \$exit_code)" | tee -a "\$log_file"
    if [ "\$terminate_loop" = true ]; then
        echo "Shutdown requested, exiting loop." | tee -a "\$log_file"; break
    fi
    echo "Restarting in \$restart_delay second(s)..." | tee -a "\$log_file"
    sleep "\$restart_delay"
done
echo "Server loop terminated."
EOF

chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$install_dir/start.sh" "$server_binary" || true
chmod 755 "$install_dir/start.sh" "$server_binary" || true

# Optionally create systemd service
service_name="blockheads-server.service"
if [ "$want_systemd" = true ]; then
    cat > "/etc/systemd/system/$service_name" <<SVC
[Unit]
Description=The Blockheads Server
After=network.target

[Service]
Type=simple
User=$ORIGINAL_USER
WorkingDirectory=$install_dir
ExecStart=$install_dir/start.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload || true
    if ! systemctl enable --now "$service_name" >/dev/null 2>&1; then
        echo "Warning: could not enable/start systemd service automatically. You can start it with: sudo systemctl start $service_name"
    fi
fi

# Final message
echo "================================================================"
echo "Installation completed in: $install_dir"
echo "Executable: $server_binary"
echo "Start script: $install_dir/start.sh"
echo "World ID: $world_id  Port: $server_port"
if [ "$want_systemd" = true ]; then
    echo "Systemd service: /etc/systemd/system/$service_name"
fi

echo "To run the server as a normal (non-root) user:"
echo "  cd $install_dir && ./start.sh"

echo "To monitor logs in real time: tail -f ~/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$world_id/console.log"

echo "================================================================"

cleanup

exit 0
