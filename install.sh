#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/appblocker"
BINARY="$INSTALL_DIR/appblocker"
PLIST_NAME="com.user.appblocker"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "Checking for Swift compiler..."
if ! command -v swiftc &>/dev/null; then
    echo "ERROR: swiftc not found. Run: xcode-select --install"
    exit 1
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

echo "Compiling blocker.swift..."
swiftc -framework Cocoa "$SCRIPT_DIR/blocker.swift" -o "$BINARY"
echo "Compiled to $BINARY"

CONFIG_FILE="$CONFIG_DIR/blocked.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "# AppBlocker blocked bundle IDs — one per line" > "$CONFIG_FILE"
    echo "# Example: com.apple.chess" >> "$CONFIG_FILE"
fi

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/stderr.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load -w "$PLIST_PATH"

echo ""
echo "AppBlocker installed and running!"
echo "Add apps: bash manage.sh add \"Slack\""
echo "List blocked: bash manage.sh list"
