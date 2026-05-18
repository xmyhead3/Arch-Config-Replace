#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# VPN QUICK MANAGER — Toggle ProtonVPN WireGuard connection
# -----------------------------------------------------------------------------
# Detects available VPN connections via NetworkManager and toggles them.
# State tracked in ~/.cache/qs_vpn

CACHE_DIR="$HOME/.cache"
STATE_FILE="$CACHE_DIR/qs_vpn"

# Auto-detect the first WireGuard VPN connection in NetworkManager
detect_vpn() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep -i 'wireguard' | head -1 | cut -d: -f1
}

VPN_NAME="${2:-$(detect_vpn)}"

case "${1:-toggle}" in
    status)
        if [ -n "$VPN_NAME" ] && nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -qi "$VPN_NAME"; then
            echo "active"
        else
            echo "inactive"
        fi
        exit 0
        ;;
    on)
        if [ -z "$VPN_NAME" ]; then
            notify-send -a "VPN" "No WireGuard VPN found" "Create one in NetworkManager first"
            exit 1
        fi
        nmcli connection up "$VPN_NAME" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "active" > "$STATE_FILE"
            notify-send -a "VPN" "🔒 VPN Connected" "$VPN_NAME"
        else
            notify-send -u critical -a "VPN" "VPN connection failed" "Could not connect to $VPN_NAME"
        fi
        ;;
    off)
        if [ -z "$VPN_NAME" ]; then exit 1; fi
        nmcli connection down "$VPN_NAME" 2>/dev/null
        echo "inactive" > "$STATE_FILE"
        notify-send -a "VPN" "🔓 VPN Disconnected" "$VPN_NAME"
        ;;
    toggle|*)
        if [ -n "$VPN_NAME" ] && nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -qi "$VPN_NAME"; then
            exec "$0" off "$VPN_NAME"
        else
            exec "$0" on "$VPN_NAME"
        fi
        ;;
esac
