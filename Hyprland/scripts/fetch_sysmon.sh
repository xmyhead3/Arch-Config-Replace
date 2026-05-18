#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SYSTEM MONITOR FETCHER — Outputs JSON with CPU, RAM, disk, network data
# -----------------------------------------------------------------------------

# CPU usage (1s average)
CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2 + $4}' || echo "0")
CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f", $1/1000}' || echo "0")

# RAM
MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}' || echo "0")
MEM_PERC=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%.0f", $3/$2*100}' || echo "0")

# Disk
DISK_ROOT=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
DISK_HOME=$(df -h /home 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

# GPU
GPU_INFO=""
if command -v nvidia-smi &>/dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
fi

# Network
NET_IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1 || echo "wlan0")
NET_RX=$(cat /sys/class/net/"$NET_IFACE"/statistics/rx_bytes 2>/dev/null || echo "0")
NET_TX=$(cat /sys/class/net/"$NET_IFACE"/statistics/tx_bytes 2>/dev/null || echo "0")

# Uptime
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")

# Process count
PROC_COUNT=$(ps aux --no-headers 2>/dev/null | wc -l || echo "0")

python3 << EOF
import json
data = {
    "cpu": float("${CPU_USAGE:-0}"),
    "cpu_temp": float("${CPU_TEMP:-0}"),
    "mem_total": int("${MEM_TOTAL:-0}"),
    "mem_used": int("${MEM_USED:-0}"),
    "mem_perc": int("${MEM_PERC:-0}"),
    "disk_root": int("${DISK_ROOT:-0}"),
    "disk_home": int("${DISK_HOME:-0}"),
    "gpu": "${GPU_INFO:-not available}",
    "net_rx": int("${NET_RX:-0}"),
    "net_tx": int("${NET_TX:-0}"),
    "uptime": "${UPTIME:-unknown}",
    "processes": int("${PROC_COUNT:-0}")
}
print(json.dumps(data))
EOF
