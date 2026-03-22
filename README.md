# AppBlocker

A lightweight macOS app blocker that prevents specified applications from running. Built with Swift, runs as a LaunchAgent daemon.

## How it works

AppBlocker runs in the background and watches for app launches. When a blocked app is detected, it's immediately force-terminated. It also kills any already-running blocked apps on startup.

Configuration is a simple text file (`~/.config/appblocker/blocked.txt`) containing one bundle ID per line. Changes take effect immediately — no restart needed.

## Requirements

- macOS
- Swift compiler (`xcode-select --install`)

## Install

```bash
git clone https://github.com/YOUR_USERNAME/appblocker.git
cd appblocker
bash install.sh
```

This compiles the Swift binary, installs it to `~/.local/bin/appblocker`, and registers a LaunchAgent that starts automatically at login.

## Usage

```bash
# Block an app by name
bash manage.sh add "Slack"

# Block by bundle ID directly
bash manage.sh add com.tinyspeck.slackmacgap

# List blocked apps
bash manage.sh list

# Search installed apps for bundle IDs
bash manage.sh find "chrome"

# Interactive unblock
bash manage.sh remove

# Check daemon status
bash manage.sh status

# View kill log
bash manage.sh log

# Uninstall (keeps config)
bash manage.sh uninstall
```

## Files

| File | Purpose |
|------|---------|
| `blocker.swift` | Main daemon — watches for app launches and kills blocked apps |
| `install.sh` | Compiles the binary and sets up the LaunchAgent |
| `manage.sh` | CLI tool for adding/removing blocked apps |
| `~/.config/appblocker/blocked.txt` | List of blocked bundle IDs |
| `~/.config/appblocker/appblocker.log` | Kill log |

## Uninstall

```bash
bash manage.sh uninstall
```

This stops the daemon and removes the binary and LaunchAgent plist. Your blocked apps config is kept at `~/.config/appblocker/` in case you reinstall.
