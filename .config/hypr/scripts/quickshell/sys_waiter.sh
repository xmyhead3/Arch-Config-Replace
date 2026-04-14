#!/usr/bin/env bash

# Debounce increased slightly to prevent tight loops on grouped events
sleep 0.5

# Kill any child listening jobs gracefully
trap 'kill -TERM $(jobs -p) 2>/dev/null; wait $(jobs -p) 2>/dev/null' EXIT

# Wrap each listener in a subshell that sleeps infinitely if the command fails.

# 1. Volume: Wait for actual volume changes, completely ignore sink-input spam
( pactl subscribe 2>/dev/null | grep --line-buffered -m 1 "Event 'change' on sink " || sleep infinity ) &

# 2. Network: Only trigger on actual connection/disconnection events
( nmcli monitor 2>/dev/null | grep --line-buffered -m 1 -E "connected|disconnected" || sleep infinity ) &

# 3. Bluetooth: Stop matching the header! Match actual string properties changing.
( dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" 2>/dev/null | grep --line-buffered -m 1 "string " || sleep infinity ) &

# 4. Battery: Ignore minor voltage fluctuations, wait for actual percentage/state changes
( udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered -m 1 "BAT" || sleep infinity ) &

# Failsafe: Force a silent UI refresh every 60 seconds
sleep 60 &

# Wait for the *first* background job to successfully complete an event
wait -n

# Output a signal to ensure Quickshell registers the stream completion
echo "trigger"
