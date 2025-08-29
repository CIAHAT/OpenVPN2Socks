#!/bin/bash

# --- File and Directory Definitions ---
SETUP_SCRIPT="./setup-vpn.sh"
CLEANUP_SCRIPT="./cleanup-vpn.sh"
CONFIG_BASE_DIR="/etc/openvpn/"
LOG_FILE="./script_debug.log"

# --- Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'

# --- Utility Functions ---

function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

function error_message() {
    log_message "❌ Error: $1"
}

function check_prerequisites() {
    if [ ! -f "$SETUP_SCRIPT" ] || [ ! -x "$SETUP_SCRIPT" ]; then
        error_message "setup-vpn.sh not found or not executable. Please make sure it's in the same directory and has execute permissions."
        exit 1
    fi
    if [ ! -f "$CLEANUP_SCRIPT" ] || [ ! -x "$CLEANUP_SCRIPT" ]; then
        error_message "cleanup-vpn.sh not found or not executable. Please make sure it's in the same directory and has execute permissions."
        exit 1
    fi
    if ! command -v curl &>/dev/null; then
        echo -e "📦 Installing 'curl'..."
        sudo apt-get update && sudo apt-get install -y curl
    fi
    if ! command -v jq &>/dev/null; then
        echo -e "📦 Installing 'jq'..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
}

function is_port_in_use() {
    local port="$1"
    if ss -tuln | grep -q ":$port "; then
        return 0
    fi
    return 1
}

function get_proxy_ip_info() {
    local port="$1"
    local json_output=$(curl --silent --connect-timeout 5 --proxy socks5h://127.0.0.1:"$port" ipinfo.io 2>/dev/null)
    if echo "$json_output" | grep -q '"ip"'; then
        echo "$json_output"
    else
        echo "{\"ip\":\"N/A\", \"city\":\"N/A\", \"country\":\"N/A\"}"
    fi
}

function get_service_status() {
    local port="$1"
    local service_name="openvpn-socks-$port.service"
    if sudo systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}🟢 Running${NC}"
    elif sudo systemctl is-failed --quiet "$service_name"; then
        echo -e "${RED}🔴 Failed${NC}"
    else
        echo -e "${YELLOW}⚪ Stopped${NC}"
    fi
}

function get_configs_array() {
    local configs=""
    for dir in "$CONFIG_BASE_DIR"*/; do
        if [[ "$dir" =~ ([0-9]+)/$ ]]; then
            local port="${BASH_REMATCH[1]}"
            local original_file="client.conf"
            if [ -f "${dir}name.txt" ]; then
                original_file=$(cat "${dir}name.txt")
            fi
            
            local status=$(get_service_status "$port")
            local ip_info="N/A"
            if [[ "$status" == *"Running"* ]]; then
                 ip_info=$(get_proxy_ip_info "$port" | jq -r '"\(.ip) (\(.country))"')
            fi
            configs+="$original_file|$port|$ip_info|$status\n"
        fi
    done
    echo -e "$configs"
}

function cleanup_all() {
    read -p "⚠️ Are you sure you want to DELETE ALL configurations (y/n)? " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "---"
        echo "🧹 Deleting all configurations..."
        local all_ports=$(get_configs_array | cut -d'|' -f2)
        for port in $all_ports; do
            echo "---"
            echo "Deleting config for port $port..."
            sudo "$CLEANUP_SCRIPT" "$port"
        done
        echo -e "✅ ${GREEN}All configurations deleted successfully.${NC}"
        read -p "Press Enter to return to the main menu..."
    fi
}

# --- Main Logic Functions ---

function add_new_config() {
    echo "➡️  Adding a new OpenVPN configuration..."
    
    while true; do
        read -p "1. Enter the full path to your .ovpn file: " OVPN_PATH
        OVPN_PATH=$(eval echo "$OVPN_PATH")
        if [ ! -f "$OVPN_PATH" ]; then
            error_message "File not found at '$OVPN_PATH'. Please check the path and try again."
            continue
        fi
        break
    done

    while true; do
        echo "---"
        echo "💡 Currently used ports:"
        local used_ports=$(get_configs_array | cut -d'|' -f2)
        if [ -n "$used_ports" ]; then
            for p in $used_ports; do
                echo "  - $p"
            done
        else
            echo "  (No ports currently in use)"
        fi
        read -p "2. Enter the port for the SOCKS5 proxy: " SOCKS_PORT
        if [[ ! "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then
            error_message "Please enter a valid number for the port."
            continue
        fi
        if is_port_in_use "$SOCKS_PORT"; then
            error_message "Port $SOCKS_PORT is already in use by another process. Please choose another one."
            continue
        fi
        local found=false
        for p in $used_ports; do
            if [ "$p" == "$SOCKS_PORT" ]; then
                found=true
                break
            fi
        done
        if [ "$found" == "true" ]; then
            error_message "A configuration for port $SOCKS_PORT already exists. Please delete it first or choose another one."
            continue
        fi
        break
    done

    read -p "3. Enter OpenVPN username (leave blank if not needed): " VPN_USER
    if [ -n "$VPN_USER" ]; then
        read -s -p "4. Enter OpenVPN password: " VPN_PASS
        echo
    else
        VPN_USER="N/A"
        VPN_PASS="N/A"
    fi
    
    echo "---"
    echo -e "🛠️  Running setup for port ${CYAN}$SOCKS_PORT${NC}..."
    sudo "$SETUP_SCRIPT" "$OVPN_PATH" "$SOCKS_PORT" "$VPN_USER" "$VPN_PASS"
    if [ $? -ne 0 ]; then
        error_message "Setup script failed. Please check the logs."
        return
    fi
    
    echo -e "✅ ${GREEN}Configuration for port $SOCKS_PORT has been added and started.${NC}"
    echo "---"
    read -p "Press Enter to return to the main menu..."
}

function display_main_menu() {
    echo -e "${BLUE}---${NC}"
    echo -e "${CYAN}VPN Manager - Main Menu${NC}"
    echo -e "${BLUE}---${NC}"
    echo "Current Configurations:"
    local configs_output
    configs_output=$(get_configs_array)
    if [ -z "$configs_output" ]; then
        echo "  (No configurations found. Please add a new one.)"
    else
        local i=1
        while IFS= read -r line; do
            local file_name=$(echo "$line" | cut -d'|' -f1)
            local port=$(echo "$line" | cut -d'|' -f2)
            local ip_info=$(echo "$line" | cut -d'|' -f3)
            local status=$(echo "$line" | cut -d'|' -f4)
            echo "$i. File: $file_name | Port: $port | IP: $ip_info | Status: $status"
            ((i++))
        done <<< "$configs_output"
    fi
    echo -e "${BLUE}---${NC}"
    echo "Options:"
    echo "1. Add new OpenVPN Config"
    echo "2. Manage existing configs"
    echo "3. Clean up ALL configurations"
    echo "4. Exit"
    echo -e "${BLUE}---${NC}"
}

function manage_configs() {
    while true; do
        clear
        echo -e "${BLUE}---${NC}"
        echo -e "${CYAN}Manage Configurations${NC}"
        echo -e "${BLUE}---${NC}"
        local configs
        configs=$(get_configs_array)
        if [ -z "$configs" ]; then
            echo "  (No configurations to manage.)"
            echo -e "${BLUE}---${NC}"
            read -p "Press Enter to return to the main menu..."
            return
        fi
        
        local i=1
        while IFS= read -r config_line; do
            local file_name=$(echo "$config_line" | cut -d'|' -f1)
            local port=$(echo "$config_line" | cut -d'|' -f2)
            local status=$(echo "$config_line" | cut -d'|' -f4)
            echo "$i. File: $file_name | Port: $port | Status: $status"
            ((i++))
        done <<< "$configs"
        
        echo -e "${BLUE}---${NC}"
        read -p "Select a number to manage, or 'q' to go back: " choice
        
        if [ "$choice" == "q" ]; then
            return
        fi

        local selected_config
        selected_config=$(echo -e "$configs" | sed -n "${choice}p")
        if [ -z "$selected_config" ]; then
            error_message "Invalid selection. Please try again."
            sleep 1
            continue
        fi

        local port=$(echo "$selected_config" | cut -d'|' -f2)
        
        while true; do
            clear
            echo -e "${BLUE}---${NC}"
            echo -e "${CYAN}Managing Configuration for Port: ${MAGENTA}$port${NC}"
            echo -e "${BLUE}---${NC}"
            echo "1. Show logs"
            echo "2. Restart"
            echo "3. Stop"
            echo "4. Start"
            echo "5. Show Final IP"
            echo "6. Delete this configuration"
            echo "7. Back to manage menu"
            echo -e "${BLUE}---${NC}"
            read -p "Enter your choice: " manage_choice
            
            case "$manage_choice" in
                1)
                    echo "---"
                    echo "Displaying logs for port $port..."
                    echo "---"
                    sudo journalctl -u "openvpn-socks-$port.service" -f
                    read -p "Press Enter to continue..."
                    ;;
                2)
                    echo "---"
                    echo "Restarting service for port $port..."
                    sudo systemctl restart "openvpn-socks-$port.service"
                    echo "---"
                    read -p "Press Enter to continue..."
                    ;;
                3)
                    echo "---"
                    echo "Stopping service for port $port..."
                    sudo systemctl stop "openvpn-socks-$port.service"
                    echo "---"
                    read -p "Press Enter to continue..."
                    ;;
                4)
                    echo "---"
                    echo "Starting service for port $port..."
                    sudo systemctl start "openvpn-socks-$port.service"
                    echo "---"
                    read -p "Press Enter to continue..."
                    ;;
                5)
                    echo "---"
                    echo "Fetching final IP information for port $port..."
                    local ip_info=$(get_proxy_ip_info "$port")
                    echo "$ip_info" | jq
                    echo "---"
                    read -p "Press Enter to continue..."
                    ;;
                6)
                    read -p "⚠️ Are you sure you want to DELETE this configuration (y/n)? " confirm
                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                        echo "---"
                        echo "Deleting configuration for port $port..."
                        sudo "$CLEANUP_SCRIPT" "$port"
                        echo -e "✅ ${GREEN}Configuration deleted successfully.${NC}"
                        read -p "Press Enter to return to main menu..."
                        return
                    fi
                    ;;
                7)
                    break
                    ;;
                *)
                    error_message "Invalid option. Please try again."
                    sleep 1
                    ;;
            esac
        done
    done
}

# --- Main Script Loop ---

check_prerequisites

while true; do
    clear
    display_main_menu
    read -p "Enter your choice: " main_choice

    case "$main_choice" in
        1)
            add_new_config
            ;;
        2)
            manage_configs
            ;;
        3)
            cleanup_all
            ;;
        4)
            echo "Exiting. Goodbye!"
            exit 0
            ;;
        *)
            error_message "Invalid option. Please try again."
            sleep 1
            ;;
    esac
done
