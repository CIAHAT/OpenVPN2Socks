#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

OVPN_PATH="$1"
SOCKS_PORT="$2"
VPN_USER="$3"
VPN_PASS="$4"

if [ -z "$OVPN_PATH" ] || [ -z "$SOCKS_PORT" ]; then
    echo -e "❌ ${RED}Error: Missing arguments.${NC}"
    echo "Usage: $0 <path_to_ovpn_file> <socks_port> [vpn_username] [vpn_password]"
    exit 1
fi

if [ ! -f "$OVPN_PATH" ]; then
    echo -e "❌ ${RED}File does not exist at '$OVPN_PATH'. Exiting.${NC}"
    exit 1
fi

echo "---"
echo "🛠️ Starting setup for $OVPN_PATH on port $SOCKS_PORT..."
echo "---"

# Prerequisites
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://get.docker.com | sh
fi

if ! command -v openvpn &>/dev/null; then
    echo "Installing OpenVPN..."
    sudo apt-get install -y openvpn
fi

sudo systemctl enable docker &>/dev/null
sudo systemctl start docker

# Cleanup previous config
if [ -d "/etc/openvpn/$SOCKS_PORT" ]; then
    echo "Cleaning previous configuration for port $SOCKS_PORT..."
    sudo docker stop "openvpn-socks-$SOCKS_PORT" &>/dev/null || true
    sudo docker rm "openvpn-socks-$SOCKS_PORT" &>/dev/null || true
    sudo systemctl disable "openvpn-socks-$SOCKS_PORT.service" &>/dev/null || true
    sudo rm -f "/etc/systemd/system/openvpn-socks-$SOCKS_PORT.service"
    sudo rm -rf "/etc/openvpn/$SOCKS_PORT"
    sudo systemctl daemon-reload
fi

# OpenVPN config copy
CONFIG_DIR="/etc/openvpn/$SOCKS_PORT"
sudo mkdir -p "$CONFIG_DIR"

CONF_PATH="$CONFIG_DIR/client.conf"
sudo cp "$OVPN_PATH" "$CONF_PATH"

# Save the original file name
sudo bash -c "echo '$(basename "$OVPN_PATH")' > '$CONFIG_DIR/name.txt'"

# Remove any old auth-user-pass line
sudo sed -i '/^auth-user-pass/d' "$CONF_PATH"

AUTH_FILE="$CONFIG_DIR/auth.txt"
if [ -n "$VPN_USER" ] && [ "$VPN_USER" != "N/A" ]; then
    echo "Saving credentials to auth.txt..."
    sudo bash -c "echo '$VPN_USER' > '$AUTH_FILE'"
    sudo bash -c "echo '$VPN_PASS' >> '$AUTH_FILE'"
    sudo chmod 600 "$AUTH_FILE"
    awk '
    /dev tun/ {
        print;
        print "auth-user-pass auth.txt";
        next;
    }
    { print; }
    ' "$CONF_PATH" > /tmp/client.tmp && sudo mv /tmp/client.tmp "$CONF_PATH"
fi

# Docker image and container
CONTAINER_NAME="openvpn-socks-$SOCKS_PORT"
DOCKER_IMAGE="kizzx2/openvpn-client-socks"
VOLUME_MOUNT="$CONFIG_DIR:/etc/openvpn:ro"
DOCKER_RUN_ARGS="--cap-add=NET_ADMIN --device=/dev/net/tun -v $VOLUME_MOUNT -p $SOCKS_PORT:1080"

echo "Pulling Docker image..."
sudo docker pull $DOCKER_IMAGE >/dev/null

echo "Running Docker container for test (will be managed by systemd)..."
sudo docker stop "$CONTAINER_NAME" &>/dev/null || true
sudo docker rm "$CONTAINER_NAME" &>/dev/null || true
sudo docker run -d --name "$CONTAINER_NAME" $DOCKER_RUN_ARGS $DOCKER_IMAGE

# Create systemd service file with correct restart/run logic
SERVICE_FILE="/etc/systemd/system/$CONTAINER_NAME.service"
sudo bash -c "cat > '$SERVICE_FILE' <<EOF
[Unit]
Description=OpenVPN SOCKS5 Proxy via Docker for port $SOCKS_PORT
After=network-online.target docker.service
Wants=network-online.target

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm $CONTAINER_NAME
ExecStart=/usr/bin/docker run --rm --name $CONTAINER_NAME $DOCKER_RUN_ARGS $DOCKER_IMAGE
ExecStop=/usr/bin/docker stop $CONTAINER_NAME

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable "$CONTAINER_NAME" &>/dev/null
sudo systemctl restart "$CONTAINER_NAME"

sleep 10
if sudo systemctl is-active --quiet "$CONTAINER_NAME"; then
    echo -e "✅ ${GREEN}Setup completed successfully for port $SOCKS_PORT.${NC}"
    echo "---"
    echo "Displaying service logs..."
    echo "---"
    sudo journalctl -u "$CONTAINER_NAME" -n 50 --no-pager
    exit 0
else
    echo -e "❌ ${RED}Setup failed for port $SOCKS_PORT.${NC}"
    sudo journalctl -u "$CONTAINER_NAME" -n 50 --no-pager
    exit 1
fi
