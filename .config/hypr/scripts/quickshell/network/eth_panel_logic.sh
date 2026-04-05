#!/usr/bin/env bash

# Find the active ethernet device
ETH_DEV=$(nmcli -t -f DEVICE,TYPE,STATE d | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')

# If no device is connected, return offline state
if [[ -z "$ETH_DEV" ]]; then
    echo '{ "power": "off", "connected": null }'
    exit 0
fi

# Fetch connection statistics
IP=$(ip -4 addr show dev "$ETH_DEV" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
[ -z "$IP" ] && IP="No IP"

SPEED=$(cat /sys/class/net/"$ETH_DEV"/speed 2>/dev/null)
[ -n "$SPEED" ] && SPEED="${SPEED} Mbps" || SPEED="Unknown"

MAC=$(cat /sys/class/net/"$ETH_DEV"/address 2>/dev/null)
PROFILE=$(nmcli -t -f NAME,DEVICE c show --active | grep "$ETH_DEV" | cut -d: -f1 | head -n1)
[ -z "$PROFILE" ] && PROFILE="Wired Connection"

CONNECTED_JSON=$(jq -n \
    --arg id "$ETH_DEV" \
    --arg name "$PROFILE" \
    --arg icon "󰈀" \
    --arg ip "$IP" \
    --arg speed "$SPEED" \
    --arg mac "$MAC" \
    '{id: $id, name: $name, icon: $icon, ip: $ip, speed: $speed, mac: $mac}')

echo $(jq -n \
    --arg power "on" \
    --argjson connected "$CONNECTED_JSON" \
    '{power: $power, connected: $connected}')
