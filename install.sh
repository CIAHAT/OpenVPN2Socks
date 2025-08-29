#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration Variables ---
# The official repository URL
REPO_URL="https://github.com/CIAHAT/OpenVPN2Socks.git"
# The directory where the application will be installed
INSTALL_DIR="/opt/OpenVPN2Socks"
# The name of the command to run the manager
EXECUTABLE_NAME="open2socks"
# The full path for the command's symlink
EXECUTABLE_PATH="/usr/local/bin/$EXECUTABLE_NAME"

# --- Color Codes ---
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🚀 Starting Open2Socks Manager installation..."

# --- 1. System Prerequisites ---
echo "📦 Checking for required packages (git, curl)..."
if ! command -v git &> /dev/null || ! command -v curl &> /dev/null; then
    echo "Git or Curl is not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y git curl
fi

# --- 2. Clone or Update Repository ---
# Check if the installation directory already exists
if [ -d "$INSTALL_DIR" ]; then
    echo "✔️ Previous installation found in $INSTALL_DIR. Updating..."
    cd "$INSTALL_DIR"
    # Stash local changes if any, and pull the latest version
    sudo git reset --hard HEAD
    sudo git pull
else
    echo "📥 Cloning repository into $INSTALL_DIR..."
    # Clone the repository from GitHub
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# --- 3. Set Script Permissions ---
echo "🔧 Setting execute permissions for all shell scripts..."
sudo chmod +x vpn-manager.sh setup-vpn.sh cleanup-vpn.sh

# --- 4. Create System-Wide Command ---
echo "🔗 Creating system-wide command '$EXECUTABLE_NAME'..."
# Remove the symlink if it already exists to avoid errors
if [ -L "$EXECUTABLE_PATH" ]; then
    sudo rm "$EXECUTABLE_PATH"
fi
# Create a symbolic link from the manager script to a directory in the system's PATH
sudo ln -s "$INSTALL_DIR/vpn-manager.sh" "$EXECUTABLE_PATH"

echo -e "${GREEN}✅ Installation/Update complete!${NC}"
echo "You can now run the manager from anywhere by typing: $EXECUTABLE_NAME"