#!/bin/bash

#===============================================================================================
#   frp a fast reverse proxy Installer Script
#
#   - Fetches the latest version of frp for Linux based on system architecture.
#   - Verifies the download with SHA256 checksum.
#   - Installs frps and frpc to /usr/local/bin.
#   - Creates a configuration directory at /etc/frp.
#   - Sets up a systemd service for frps.
#
#   Usage:
#       curl -L -s -o install_frp.sh <URL_TO_THIS_SCRIPT>
#       chmod +x install_frp.sh
#       sudo ./install_frp.sh
#===============================================================================================

set -e
set -o pipefail

# -- Script Configuration --
# Installation directory for frp binaries
INSTALL_DIR="/usr/local/bin"
# Configuration directory for frp
CONFIG_DIR="/etc/frp"
# GitHub repository
REPO="fatedier/frp"

# -- Color Definitions --
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# -- Prerequisite Checks --
# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Please use sudo."
fi

# Check for required tools
for cmd in curl tar grep jq; do
    if ! command -v $cmd &> /dev/null; then
        error "Required command '$cmd' is not installed. Please install it first."
    fi
done

# -- Main Logic --
main() {
    # 1. Detect Architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac
    OS="linux"
    info "Detected OS: $OS, Arch: $ARCH"

    # 2. Get Latest Version from GitHub API
    info "Fetching the latest frp version..."
    LATEST_VERSION=$(curl --silent "https://api.github.com/repos/$REPO/releases/latest" | jq -r .tag_name | sed 's/v//')
    if [ -z "$LATEST_VERSION" ]; then
        error "Failed to fetch the latest frp version. Check network or API rate limits."
    fi
    info "Latest frp version is: $LATEST_VERSION"

    # 3. Download and Verify
    FILENAME="frp_${LATEST_VERSION}_${OS}_${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/v${LATEST_VERSION}/${FILENAME}"
    CHECKSUM_FILENAME="frp_${LATEST_VERSION}_checksums.txt"
    CHECKSUM_URL="https://github.com/$REPO/releases/download/v${LATEST_VERSION}/${CHECKSUM_FILENAME}"
    
    TMP_DIR="/tmp/frp_install"
    mkdir -p "$TMP_DIR"
    
    info "Downloading frp package from: $DOWNLOAD_URL"
    curl -L -o "$TMP_DIR/$FILENAME" "$DOWNLOAD_URL"
    
    info "Downloading checksums from: $CHECKSUM_URL"
    curl -L -o "$TMP_DIR/$CHECKSUM_FILENAME" "$CHECKSUM_URL"

    info "Verifying SHA256 checksum..."
    (cd "$TMP_DIR" && grep "$FILENAME" "$CHECKSUM_FILENAME" | sha256sum -c --strict)
    if [ $? -ne 0 ]; then
        error "Checksum verification failed! The downloaded file may be corrupt or tampered with."
    fi
    info "Checksum verification successful."

    # 4. Install
    info "Extracting frp package..."
    tar -xzf "$TMP_DIR/$FILENAME" -C "$TMP_DIR"
    
    EXTRACTED_DIR_NAME="frp_${LATEST_VERSION}_${OS}_${ARCH}"
    
    info "Installing frps and frpc to $INSTALL_DIR..."
    install -m 755 "$TMP_DIR/$EXTRACTED_DIR_NAME/frps" "$INSTALL_DIR"
    install -m 755 "$TMP_DIR/$EXTRACTED_DIR_NAME/frpc" "$INSTALL_DIR"
    
    # 5. Create Configuration
    info "Creating configuration directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    
    if [ -f "$CONFIG_DIR/frps.toml" ]; then
        warn "$CONFIG_DIR/frps.toml already exists. Skipping creation of default config."
    else
        info "Creating default frps.toml with mTLS configuration..."
        cat > "$CONFIG_DIR/frps.toml" << EOF
# frps.toml - frp Server Configuration
# For detailed documentation, see: https://gofrp.org/docs/

# Main port for frp client-server communication.
bindPort = 7000

# Web server for the frp dashboard.
webServer.port = 7500
webServer.user = "admin"
webServer.password = "your_secure_password_here" # CHANGE THIS!

# --- mTLS Authentication ---
# This is the core of the secure setup.
# Place your generated certificates (ca.crt, server.crt, server.key) in $CONFIG_DIR
transport.tls.force = true
transport.tls.certFile = "$CONFIG_DIR/server.crt"
transport.tls.keyFile = "$CONFIG_DIR/server.key"
transport.tls.trustedCaFile = "$CONFIG_DIR/ca.crt"
EOF
    fi

    # 6. Setup Systemd Service
    info "Creating systemd service file for frps..."
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=frp Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=5s
# Make sure the paths to your frps binary and config file are correct.
ExecStart=$INSTALL_DIR/frps -c $CONFIG_DIR/frps.toml

[Install]
WantedBy=multi-user.target
EOF

    info "Reloading systemd daemon..."
    systemctl daemon-reload
    info "Enabling frps service to start on boot..."
    systemctl enable frps

    # 7. Cleanup
    info "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"

    # 8. Final Instructions
    echo
    info "================================================================="
    info " frp version $LATEST_VERSION has been successfully installed!"
    info "================================================================="
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "1. Edit the server configuration file:"
    echo "   sudo vim $CONFIG_DIR/frps.toml"
    echo "   (Remember to set a strong password for the web server)"
    echo
    echo "2. Place your certificates in '$CONFIG_DIR/':"
    echo "   - ca.crt"
    echo "   - server.crt"
    echo "   - server.key"
    echo
    echo "3. Start the frps service:"
    echo "   sudo systemctl start frps"
    echo
    echo "4. Check the service status:"
    echo "   sudo systemctl status frps"
    echo "================================================================="
}

# Run the main function
main
