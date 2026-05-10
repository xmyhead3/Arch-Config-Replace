> [!WARNING]
> This installer sends telemetry that helps me debug problems

# WifeRice

A feature-rich Hyprland dotfiles configuration with integrated system monitoring, battery alerts, and automated setup.

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/eprahemi/WifeRice/main/install.sh)"
```

## Features

- **Hyprland Desktop** — Pre-configured window manager setup with Quickshell widgets (app launcher, music, calendar, network, battery, volume, clipboard)
- **Automated Setup** — Single-command install: detects your hardware, installs dependencies, clones configs, and applies them
- **System Monitoring** — 13 background scripts report hardware health, disk usage, network issues, NVIDIA status, package errors, and more to Discord
- **Battery Alerts** — Audio + desktop notifications at 20%/10%/5%, auto-suspend at 3%
- **Theming** — Matugen-based color generation from wallpaper, applied across GTK, Qt, SDDM, and shell

## Configuration

After installation, settings are managed through `~/.config/hypr/settings.json`. Edit this file and changes apply automatically.

## Contact

- GitHub Issues — Bug reports and feature requests
- Discord — `discord.gg/eprahemi`
