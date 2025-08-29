#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Input Validation ---
SOCKS_PORT="$1"

if [ -z "$SOCKS_PORT" ]; then
    echo "❌ Error: Missing SOCKS5 port argument."
    echo "Usage: $0 <socks_port>"
    exit 1
fi

echo "---"
echo "🧹 Cleaning up configuration for port $SOCKS_PORT..."
echo "---"

CONTAINER_NAME="openvpn-socks-$SOCKS_PORT"
SERVICE_NAME="openvpn-socks-$SOCKS_PORT"
CONFIG_DIR="/etc/openvpn/$SOCKS_PORT"

# Stop and disable the systemd service
systemctl stop "$SERVICE_NAME" &>/dev/null || true
systemctl disable "$SERVICE_NAME" &>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME.service"
systemctl daemon-reload

# Stop and remove the Docker container and image
docker stop "$CONTAINER_NAME" &>/dev/null || true
docker rm "$CONTAINER_NAME" &>/dev/null || true

# Remove configuration files and directory
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
fi

echo "✅ Cleanup completed successfully for port $SOCKS_PORT."

exit 0