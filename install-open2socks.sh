#!/bin/bash

set -e

GITHUB_USER="CIAHAT"
GITHUB_REPO="OpenVPN2Socks"
GITHUB_API_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/contents/"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/"

BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

echo "======================================"
echo "  Open2Socks Interactive Installer"
echo "======================================"
echo

# 1. Install dependencies
echo "Checking dependencies..."

REQUIRED_PACKAGES=("curl" "jq" "zip" "unzip" "docker.io" "openvpn")
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "Installing $pkg..."
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    else
        echo "$pkg is already installed."
    fi
done

# 2. Download all scripts from GitHub repo to /usr/local/bin
echo
echo "Downloading all scripts from GitHub..."

file_list=$(curl -s "$GITHUB_API_URL" | jq -r '.[] | select(.type=="file") | .name')

for FILE in $file_list; do
    sudo curl -fsSL "$GITHUB_RAW_BASE$FILE" -o "$BIN_DIR/$FILE"
    sudo chmod +x "$BIN_DIR/$FILE"
    echo "Downloaded and made executable: $FILE"
done

echo
echo "All scripts are installed in $BIN_DIR"

# 3. Enable and reload any required systemd services/timers
if [ -f "$BIN_DIR/open2socks-monitor.sh" ]; then
    # Optional: create or reload monitor timer if config exists
    MONITOR_CONF="/etc/openvpn/monitoring.conf"
    if [ -f "$MONITOR_CONF" ]; then
        source "$MONITOR_CONF"
        if [ -n "$MONITOR_INTERVAL" ]; then
            sudo "$BIN_DIR/open2socks" --setup-monitor-timer "$MONITOR_INTERVAL"
        fi
    fi
fi

echo
echo "======================================"
echo "Installation complete!"
echo "You can now run:"
echo
echo "    sudo open2socks"
echo
echo "======================================"
