#!/bin/bash

set -e

GITHUB_USER="CIAHAT"
GITHUB_REPO="OpenVPN2Socks"
GITHUB_API_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/contents/"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/"

BIN_DIR="/usr/local/bin"

echo "======================================"
echo "  Open2Socks Interactive Installer"
echo "======================================"
echo

# 1. Install dependencies (except docker)
REQUIRED_PACKAGES=("curl" "jq" "zip" "unzip" "openvpn")
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "Installing $pkg..."
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    else
        echo "$pkg is already installed."
    fi
done

# 2. Remove broken or conflicting docker/containerd packages if exist
if dpkg -l | grep -qE 'docker.io|containerd|containerd.io'; then
    echo "Removing any conflicting docker/containerd/containerd.io packages..."
    sudo apt-get remove -y docker.io containerd containerd.io runc
fi

# 3. Install Docker (only if not present)
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker using the official script..."
    curl -fsSL https://get.docker.com | sh
else
    echo "Docker is already installed."
fi

# 4. Download all scripts from GitHub repo to /usr/local/bin
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

echo
echo "======================================"
echo "Installation complete!"
echo "You can now run:"
echo
echo "    sudo open2socks"
echo
echo "======================================"
