#!/bin/bash

CONFIG_BASE_DIR="/etc/openvpn/"
CLEANUP_SCRIPT="/usr/local/bin/cleanup-vpn.sh"

function get_proxy_ip_info() {
    local port="$1"
    local json_output=$(curl --silent --connect-timeout 5 --proxy socks5h://127.0.0.1:"$port" ipinfo.io 2>/dev/null)
    if echo "$json_output" | grep -q '"ip"'; then
        echo "$json_output"
    else
        echo "{\"ip\":\"N/A\", \"city\":\"N/A\", \"country\":\"N/A\"}"
    fi
}

for dir in "$CONFIG_BASE_DIR"*/; do
    if [[ "$dir" =~ ([0-9]+)/$ ]]; then
        port="${BASH_REMATCH[1]}"
        service_name="openvpn-socks-$port.service"
        if systemctl is-active --quiet "$service_name"; then
            ip_info=$(get_proxy_ip_info "$port")
            ip=$(echo "$ip_info" | jq -r '.ip')
            if [ "$ip" == "N/A" ]; then
                logger "Open2Socks: Proxy $port seems down. Restarting service."
                systemctl restart "$service_name"
            fi
        fi
    fi
done
