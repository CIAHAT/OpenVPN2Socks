#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Input Validation ---
OVPN_PATH="$1"
SOCKS_PORT="$2"
VPN_USER="$3"
VPN_PASS="$4"
DB_FILE="$5" # Added database file path as an argument

if [ -z "$OVPN_PATH" ] || [ -z "$SOCKS_PORT" ]; then
    echo -e "❌ ${RED}Error: Missing arguments.${NC}"
    echo "Usage: $0 <path_to_ovpn_file> <socks_port> [vpn_username] [vpn_password] <configs_db_path>"
    exit 1
fi

if [ ! -f "$OVPN_PATH" ]; then
    echo -e "❌ ${RED}File does not exist at '$OVPN_PATH'. Exiting.${NC}"
    exit 1
fi

echo "---"
echo "🛠️ Starting setup for $OVPN_PATH on port $SOCKS_PORT..."
echo "---"

# --- Prerequisites Installation ---
if ! command -v docker &>/dev/null; then
    echo "📦 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

if ! command -v openvpn &>/dev/null; then
    echo "📦 Installing OpenVPN..."
    sudo apt-get install -y openvpn
fi

# Ensure Docker service is running
sudo systemctl enable docker &>/dev/null
sudo systemctl start docker

# --- Cleanup previous config if it exists ---
if [ -d "/etc/openvpn/$SOCKS_PORT" ]; then
    echo "🧹 Found previous configuration for port $SOCKS_PORT. Cleaning up..."
    sudo docker stop "openvpn-socks-$SOCKS_PORT" &>/dev/null || true
    sudo docker rm "openvpn-socks-$SOCKS_PORT" &>/dev/null || true
    sudo systemctl disable "openvpn-socks-$SOCKS_PORT.service" &>/dev/null || true
    sudo rm -f "/etc/systemd/system/openvpn-socks-$SOCKS_PORT.service"
    sudo rm -rf "/etc/openvpn/$SOCKS_PORT"
    sudo systemctl daemon-reload
fi

# --- OpenVPN Configuration ---
CONFIG_DIR="/etc/openvpn/$SOCKS_PORT"
sudo mkdir -p "$CONFIG_DIR"

CONF_PATH="$CONFIG_DIR/client.conf"
sudo cp "$OVPN_PATH" "$CONF_PATH"

# Save the original file name in a text file
sudo bash -c "echo '$(basename "$OVPN_PATH")' > '$CONFIG_DIR/name.txt'"

# First, remove all existing auth-user-pass lines from the copied file.
sudo sed -i '/^auth-user-pass/d' "$CONF_PATH"

# Handle credentials by creating auth.txt and adding auth-user-pass line
AUTH_FILE="$CONFIG_DIR/auth.txt"
if [ -n "$VPN_USER" ] && [ "$VPN_USER" != "N/A" ]; then
    echo "Saving credentials to auth.txt..."
    sudo bash -c "echo '$VPN_USER' > '$AUTH_FILE'"
    sudo bash -c "echo '$VPN_PASS' >> '$AUTH_FILE'"
    sudo chmod 600 "$AUTH_FILE"
    
    # Add auth-user-pass line to the config file
    awk '
    /dev tun/ {
        print;
        print "auth-user-pass auth.txt";
        next;
    }
    { print; }
    ' "$CONF_PATH" > /tmp/client.tmp && sudo mv /tmp/client.tmp "$CONF_PATH"
else
    echo "No username/password provided. Skipping authentication setup."
fi

# --- Docker Container Setup ---
CONTAINER_NAME="openvpn-socks-$SOCKS_PORT"
SERVICE_NAME="openvpn-socks-$SOCKS_PORT"

echo "📥 Pulling Docker image..."
sudo docker pull kizzx2/openvpn-client-socks >/dev/null

echo "🚀 Starting Docker container..."
sudo docker run -d \
    --name "$CONTAINER_NAME" \
    --cap-add=NET_ADMIN \
    --device=/dev/net/tun \
    -v "$CONFIG_DIR":/etc/openvpn:ro \
    -p "$SOCKS_PORT":1080 \
    kizzx2/openvpn-client-socks

# --- Systemd Service Creation ---
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

sudo bash -c "cat > '$SERVICE_FILE' <<EOF
[Unit]
Description=OpenVPN SOCKS5 Proxy via Docker for port $SOCKS_PORT
After=network-online.target docker.service
Wants=network-online.target

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a '$CONTAINER_NAME'
ExecStop=/usr/bin/docker stop '$CONTAINER_NAME'

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME" &>/dev/null
sudo systemctl start "$SERVICE_NAME"

# Check if the service started successfully before adding to DB
sleep 10 # Give the service some time to start
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "✅ ${GREEN}Setup completed successfully for port $SOCKS_PORT.${NC}"
    
    echo "---"
    echo "🔍 Displaying service logs..."
    echo "---"
    journalctl -u "$SERVICE_NAME" -f
    exit 0 # Exit with success code
else
    echo -e "❌ ${RED}Setup failed for port $SOCKS_PORT.${NC}"
    echo "Please check the logs for details."
    journalctl -u "$SERVICE_NAME" -f
    exit 1 # Exit with failure code
fi