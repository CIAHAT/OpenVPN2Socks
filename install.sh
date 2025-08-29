#!/bin/bash

# Exit on any error
set -e

# --- Variables ---
REPO_URL="https://github.com/YourUsername/open2socks-manager.git" # <-- !!! آدرس ریپازیتوری خودتان را جایگزین کنید
INSTALL_DIR="/opt/open2socks-manager"
EXECUTABLE_PATH="/usr/local/bin/open2socks"
GREEN='\033[0;32m'
NC='\033[0m'

echo "🚀 Starting Open2Socks Manager installation..."

# --- Prerequisites ---
echo "📦 Checking for Git..."
if ! command -v git &> /dev/null; then
    echo "Git not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y git
fi

# --- Installation ---
if [ -d "$INSTALL_DIR" ]; then
    echo "✔️ Previous installation found. Updating..."
    cd "$INSTALL_DIR"
    sudo git pull
else
    echo "📥 Cloning repository..."
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# --- Make scripts executable ---
echo "🔧 Setting permissions..."
sudo chmod +x vpn-manager.sh setup-vpn.sh cleanup-vpn.sh

# --- Create symlink for easy access ---
echo "🔗 Creating command 'open2socks'..."
if [ -L "$EXECUTABLE_PATH" ]; then
    sudo rm "$EXECUTABLE_PATH"
fi
sudo ln -s "$INSTALL_DIR/vpn-manager.sh" "$EXECUTABLE_PATH"

echo -e "${GREEN}✅ Installation/Update complete!${NC}"
echo "You can now run the manager from anywhere by typing: open2socks"