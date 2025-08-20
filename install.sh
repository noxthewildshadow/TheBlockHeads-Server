#!/bin/bash
# ======================================================
# blockheads_installer_interactive.sh
# An intuitive, beginner-friendly installer and configurator
# for The Blockheads Linux server (blockheads_server171).
# - Interactive prompts with sensible defaults
# - Non-interactive mode for automation (--yes)
# - Cross-distro package checks (apt/yum/dnf/pacman)
# - Optional dedicated system user 'blockheads'
# - Optional systemd service installation and enablement
# - UFW firewall detection & optional port opening
# - Log rotation config and daily backups script
# - Robust error handling and clear, step-by-step output
# ======================================================

set -euo pipefail
trap 'rc=$?; [ $rc -ne 0 ] && echo "Installer exited with code $rc"; exit $rc' EXIT

# -------------------------
# Defaults
# -------------------------
DEFAULT_INSTALL_DIR="/opt/blockheads"
DEFAULT_WORLD_ID="83cad395edb8d0f1912fec89508d8a1d"
DEFAULT_PORT=15151
DEFAULT_SERVICE_NAME="blockheads"
SERVER_URL="https://web.archive.org/web/20240309015235if_/https://majicdave.com/share/blockheads_server171.tar.gz"
TARBALL_NAME="blockheads_server171.tar.gz"
BINARY_NAME="blockheads_server171"

# -------------------------
# Helpers
# -------------------------
_info(){ printf "\e[32m[INFO]\e[0m %s\n" "$*"; }
_warn(){ printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
_err(){ printf "\e[31m[ERROR]\e[0m %s\n" "$*"; }

_cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

prompt_yesno(){ # prompt_yesno "Question" default_yes(true/false)
    local question="$1"; local default_yes=${2:-true}
    local def_label
    if $default_yes; then def_label="Y/n"; else def_label="y/N"; fi
    while true; do
        read -r -p "$question [$def_label]: " ans || true
        if [ -z "$ans" ]; then
            $default_yes && return 0 || return 1
        fi
        case "$ans" in
            [Yy]* ) return 0 ;; [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

read_with_default(){ # read_with_default varname prompt default
    local varname="$1"; local prompt="$2"; local default_val="$3"
    read -r -p "$prompt [$default_val]: " val || true
    if [ -z "$val" ]; then val="$default_val"; fi
    printf -v "$varname" "%s" "$val"
}

# -------------------------
# Parse args
# -------------------------
NONINTERACTIVE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) NONINTERACTIVE=true; shift ;;
        --help|-h) echo "Usage: $0 [--yes]"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# -------------------------
# Confirm root
# -------------------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    _err "This installer requires root privileges. Run with: sudo $0"
    exit 1
fi

ORIGINAL_USER=${SUDO_USER:-${USER:-root}}
_info "Installer running as root. Original user: $ORIGINAL_USER"

# -------------------------
# Gather configuration (interactive unless --yes)
# -------------------------
if ! $NONINTERACTIVE; then
    echo -e "\nWelcome to The Blockheads Server installer! I'll guide you step-by-step.\n"
    read_with_default INSTALL_DIR "Installation directory" "$DEFAULT_INSTALL_DIR"
    read_with_default WORLD_ID "World ID (identifier for your world)" "$DEFAULT_WORLD_ID"
    read_with_default SERVER_PORT "Server port" "$DEFAULT_PORT"

    prompt_yesno "Create a dedicated system user 'blockheads' to run the server (recommended)" true
    CREATE_SYSTEM_USER=$?

    prompt_yesno "Install and enable a systemd service to run the server automatically" true
    INSTALL_SYSTEMD=$?

    prompt_yesno "Open firewall port $SERVER_PORT with UFW (if installed)" true
    OPEN_FIREWALL=$?

    prompt_yesno "Enable daily automatic backups (creates a cron job)" true
    ENABLE_BACKUPS=$?
else
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    WORLD_ID="$DEFAULT_WORLD_ID"
    SERVER_PORT="$DEFAULT_PORT"
    CREATE_SYSTEM_USER=0
    INSTALL_SYSTEMD=0
    OPEN_FIREWALL=0
    ENABLE_BACKUPS=0
    _info "Running non-interactively with defaults. Use --help for options."
fi

_info "Summary of choices:"
echo "  Install dir: $INSTALL_DIR"
echo "  World ID: $WORLD_ID"
echo "  Port: $SERVER_PORT"
echo "  Create system user: $([ $CREATE_SYSTEM_USER -eq 0 ] && echo Yes || echo No)"
echo "  Install systemd: $([ $INSTALL_SYSTEMD -eq 0 ] && echo Yes || echo No)"
echo "  Open firewall: $([ $OPEN_FIREWALL -eq 0 ] && echo Yes || echo No)"
echo "  Enable backups: $([ $ENABLE_BACKUPS -eq 0 ] && echo Yes || echo No)"

if ! $NONINTERACTIVE; then
    prompt_yesno "Proceed with the installation?" true || { _info "Aborted by user."; exit 0; }
fi

# -------------------------
# Prepare install dir
# -------------------------
mkdir -p "$INSTALL_DIR"
chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"
cd "$INSTALL_DIR"
_info "Working in $INSTALL_DIR"

# -------------------------
# Install helper packages per distro if possible
# -------------------------
install_pkg_list(){
    local pkgs=("wget" "curl" "tar" "file")
    if _cmd_exists apt-get; then
        _info "Using apt to install helper packages (if missing)..."
        apt-get update -y >/dev/null
        apt-get install -y "${pkgs[@]}" >/dev/null || true
    elif _cmd_exists yum || _cmd_exists dnf; then
        _info "Using yum/dnf to install helper packages (if missing)..."
        if _cmd_exists dnf; then dnf install -y "${pkgs[@]}" >/dev/null || true; else yum install -y "${pkgs[@]}" >/dev/null || true; fi
    elif _cmd_exists pacman; then
        _info "Using pacman to install helper packages (if missing)..."
        pacman -Sy --noconfirm "${pkgs[@]}" >/dev/null || true
    else
        _warn "Could not detect package manager. Please ensure wget/curl/tar/file are installed."
    fi
}
install_pkg_list

# -------------------------
# Download and extract
# -------------------------
TMPDIR=$(mktemp -d)
TARBALL_PATH="$TMPDIR/$TARBALL_NAME"
_info "Downloading server archive..."
if _cmd_exists wget; then
    wget -q "$SERVER_URL" -O "$TARBALL_PATH" || { _err "Download failed"; exit 1; }
elif _cmd_exists curl; then
    curl -sSL "$SERVER_URL" -o "$TARBALL_PATH" || { _err "Download failed"; exit 1; }
else
    _err "Neither wget nor curl is available. Install one and retry."
    exit 1
fi

_info "Extracting archive..."
if tar xzf "$TARBALL_PATH" -C "$INSTALL_DIR"; then
    _info "Extraction complete."
else
    _err "Extraction failed. Tarball may be corrupted."; exit 1
fi

# Ensure binary exists
if [ ! -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    _err "Binary $BINARY_NAME not found in $INSTALL_DIR after extraction."; exit 1
fi
chmod +x "$INSTALL_DIR/$BINARY_NAME"
cp -n "$INSTALL_DIR/$BINARY_NAME" "$INSTALL_DIR/${BINARY_NAME}.orig" || true

# -------------------------
# Optional: create system user
# -------------------------
if [ $CREATE_SYSTEM_USER -eq 0 ]; then
    if id -u blockheads >/dev/null 2>&1; then
        _info "System user 'blockheads' already exists. Using existing user."
    else
        _info "Creating system user 'blockheads' (no shell, system account)..."
        useradd --system --no-create-home --shell /usr/sbin/nologin blockheads || true
    fi
    chown -R blockheads:blockheads "$INSTALL_DIR"
else
    chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$INSTALL_DIR"
fi

# -------------------------
# Patching (patchelf) if present
# -------------------------
if _cmd_exists patchelf; then
    _info "patchelf found — attempting to patch common missing libs if needed..."
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
        old=${pair%%:*}; new=${pair##*:}
        if patchelf --print-needed "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null | grep -q "$old"; then
            _info "Patching $old -> $new"
            if ! patchelf --replace-needed "$old" "$new" "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null; then
                _warn "patchelf failed for $old -> $new; continuing"
            fi
        fi
    done
else
    _warn "patchelf not installed. If the binary complains about missing libraries, consider installing patchelf and re-running the patch step."
fi

# -------------------------
# Create start.sh (robust and simple)
# -------------------------
cat > "$INSTALL_DIR/start.sh" <<'STARTSH'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(dirname "$(readlink -f "$0")")"
WORLD_ID="$WORLD_ID_PLACEHOLDER"
PORT="$PORT_PLACEHOLDER"
BINARY="$DIR/blockheads_server171"
LOG_DIR="$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/$WORLD_ID"
LOG_FILE="$LOG_DIR/console.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR" || true
if [ ! -x "$BINARY" ]; then chmod +x "$BINARY"; fi

echo "Starting Blockheads server (world: $WORLD_ID, port: $PORT)"
# Run in an infinite restart loop
while true; do
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] Starting server..." | tee -a "$LOG_FILE"
    (cd "$DIR" && ./blockheads_server171 -o "$WORLD_ID" -p "$PORT") 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]:-0}
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] Server exited (code $rc). Restarting in 2s..." | tee -a "$LOG_FILE"
    sleep 2
done
STARTSH

# Replace placeholders in the start.sh
sed -i "s|WORLD_ID_PLACEHOLDER|$WORLD_ID|g" "$INSTALL_DIR/start.sh"
sed -i "s|PORT_PLACEHOLDER|$SERVER_PORT|g" "$INSTALL_DIR/start.sh"
chmod 755 "$INSTALL_DIR/start.sh"

# Set ownership correctly
if [ $CREATE_SYSTEM_USER -eq 0 ]; then
    chown -R blockheads:blockheads "$INSTALL_DIR"
else
    chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$INSTALL_DIR"
fi

# -------------------------
# Create systemd service (optional)
# -------------------------
if [ $INSTALL_SYSTEMD -eq 0 ]; then
    _info "Creating systemd service: $DEFAULT_SERVICE_NAME.service"
    SERVICE_FILE="/etc/systemd/system/$DEFAULT_SERVICE_NAME.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=The Blockheads Server
After=network.target

[Service]
Type=simple
User=$( [ $CREATE_SYSTEM_USER -eq 0 ] && echo blockheads || echo "$ORIGINAL_USER" )
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$DEFAULT_SERVICE_NAME.service"
    _info "Service installed and started. Use: systemctl status $DEFAULT_SERVICE_NAME"
fi

# -------------------------
# Configure UFW (optional)
# -------------------------
if [ $OPEN_FIREWALL -eq 0 ]; then
    if _cmd_exists ufw; then
        _info "Allowing TCP port $SERVER_PORT through UFW..."
        ufw allow "$SERVER_PORT/tcp" || _warn "ufw command returned non-zero"
        _info "UFW rules updated."
    else
        _warn "UFW not found; skipping firewall step. If you use a different firewall, open TCP port $SERVER_PORT manually."
    fi
fi

# -------------------------
# Setup logrotate
# -------------------------
_info "Installing logrotate configuration for Blockheads logs."
cat > "/etc/logrotate.d/blockheads" <<EOF
$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/*/console.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# -------------------------
# Setup backups (optional via cron)
# -------------------------
if [ $ENABLE_BACKUPS -eq 0 ]; then
    _info "Creating daily backup script in $INSTALL_DIR/backup.sh and a cron job."
    cat > "$INSTALL_DIR/backup.sh" <<'BK'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(dirname "$(readlink -f "$0")")"
BACKUP_DIR="$DIR/backups"
mkdir -p "$BACKUP_DIR"
TS=$(date '+%Y%m%d-%H%M%S')
ARCHIVE="$BACKUP_DIR/blockheads-$TS.tar.gz"
# Exclude backups and logs to avoid recursion
tar --exclude='./backups' --exclude='./*.log' -czf "$ARCHIVE" -C "$DIR" .
# Keep last 14 backups
ls -1tr "$BACKUP_DIR"/blockheads-*.tar.gz | head -n -14 | xargs -r rm -f
BK
    sed -i "s|DIR=\"$(pwd)\"|DIR=\"$INSTALL_DIR\"|" "$INSTALL_DIR/backup.sh" || true
    chmod +x "$INSTALL_DIR/backup.sh"
    # Install cron job for root (runs daily at 03:30)
    (crontab -l 2>/dev/null || true) | { cat; echo "30 3 * * * $INSTALL_DIR/backup.sh >/dev/null 2>&1"; } | crontab -
    _info "Backup cron job installed (daily at 03:30). Backups stored in $INSTALL_DIR/backups"
fi

# -------------------------
# Final notes to user
# -------------------------
_info "Installation complete."
if [ $INSTALL_SYSTEMD -eq 0 ]; then
    echo "Start/stop the server with: systemctl [start|stop|status] $DEFAULT_SERVICE_NAME"
    echo "Follow logs with: journalctl -u $DEFAULT_SERVICE_NAME -f"
else
    echo "You chose not to install systemd service. Start the server manually from $INSTALL_DIR with: $INSTALL_DIR/start.sh"
fi

echo "Server binary: $INSTALL_DIR/$BINARY_NAME"
echo "Logs (per world): \$HOME/GNUstep/Library/ApplicationSupport/TheBlockheads/saves/<world_id>/console.log"
echo "Backups (if enabled): $INSTALL_DIR/backups"

echo "If something fails, check:'"
echo "  - permissions: ls -l $INSTALL_DIR"
echo "  - binary output: journalctl -u $DEFAULT_SERVICE_NAME -n 200" || true

# Cleanup
rm -rf "$TMPDIR"

exit 0
