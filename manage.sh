#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/appblocker/blocked.txt"
PLIST_NAME="com.user.appblocker"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

bundle_id_for_app() {
    local bid
    bid=$(osascript -e "id of app \"$1\"" 2>/dev/null)
    if [ -n "$bid" ]; then echo "$bid"; return; fi
    local app_path
    app_path=$(find /Applications ~/Applications -maxdepth 2 -name "${1}.app" 2>/dev/null | head -1)
    if [ -n "$app_path" ]; then
        mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null
    fi
}

cmd_add() {
    local input="$1"
    if [ -z "$input" ]; then echo "Usage: bash manage.sh add \"App Name\""; exit 1; fi
    local bid
    if [[ "$input" == *.* && "$input" != *" "* ]]; then
        bid="$input"
    else
        echo "Looking up \"$input\"..."
        bid=$(bundle_id_for_app "$input")
        if [ -z "$bid" ] || [ "$bid" = "(null)" ]; then
            echo "Could not find \"$input\". Try: bash manage.sh find \"$input\""
            exit 1
        fi
    fi
    if grep -qxF "$bid" "$CONFIG_FILE" 2>/dev/null; then
        echo "Already blocked: $bid"; exit 0
    fi
    echo "$bid" >> "$CONFIG_FILE"
    echo "Blocked: $bid (takes effect immediately)"
    pkill -f "$bid" 2>/dev/null || true
}

cmd_remove() {
    echo "Currently blocked:"; echo ""
    local i=0; declare -a entries
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        i=$((i+1)); entries+=("$line")
        printf "  [%d] %s\n" "$i" "$line"
    done < "$CONFIG_FILE"
    [ $i -eq 0 ] && echo "  (none)" && exit 0
    echo ""; read -rp "Number to remove (0=cancel): " choice
    [ "$choice" = "0" ] || [ -z "$choice" ] && exit 0
    local to_remove="${entries[$((choice-1))]}"
    sed -i '' "/^$(echo "$to_remove" | sed 's/\./\\./g')$/d" "$CONFIG_FILE"
    echo "Unblocked: $to_remove"
}

cmd_list() {
    echo ""; echo "Blocked apps:"; echo ""
    local found=0
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local name; name=$(osascript -e "name of application id \"$line\"" 2>/dev/null || echo "")
        [ -n "$name" ] && printf "  %-45s → %s\n" "$line" "$name" || printf "  %s\n" "$line"
        found=$((found+1))
    done < "$CONFIG_FILE"
    [ $found -eq 0 ] && echo "  (none)" || echo ""; echo "  Total: $found blocked"
    echo ""
}

cmd_find() {
    echo ""; [ -n "$1" ] && echo "Apps matching \"$1\":" || echo "All installed apps:"
    echo ""
    while IFS= read -r app_path; do
        local name; name=$(basename "$app_path" .app)
        [ -n "$1" ] && ! echo "$name" | grep -qi "$1" && continue
        local bid; bid=$(mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null)
        [ -n "$bid" ] && [ "$bid" != "(null)" ] && printf "  %-35s  %s\n" "$name" "$bid"
    done < <(find /Applications ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null | sort)
    echo ""
}

cmd_status() {
    echo ""
    launchctl list | grep -q "$PLIST_NAME" && echo "  Daemon: RUNNING" || echo "  Daemon: NOT running"
    local count=0
    while IFS= read -r line; do [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue; count=$((count+1)); done < "$CONFIG_FILE"
    echo "  Blocked apps: $count"
    echo "  Config: $CONFIG_FILE"
    echo "  Log: $HOME/.config/appblocker/appblocker.log"
    echo ""
}

cmd_log() {
    local logfile="$HOME/.config/appblocker/appblocker.log"
    [ -f "$logfile" ] && tail -40 "$logfile" || echo "No log yet."
}

cmd_uninstall() {
    read -rp "Remove AppBlocker? (yes/no): " c
    [ "$c" != "yes" ] && exit 0
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH" "$HOME/.local/bin/appblocker"
    echo "Uninstalled. Config kept at ~/.config/appblocker/"
}

case "${1:-help}" in
    add)       cmd_add "$2" ;;
    remove)    cmd_remove ;;
    list)      cmd_list ;;
    find)      cmd_find "$2" ;;
    status)    cmd_status ;;
    log)       cmd_log ;;
    uninstall) cmd_uninstall ;;
    *)
        echo ""
        echo "Usage: bash manage.sh <command>"
        echo "  add \"App Name\"   — block an app"
        echo "  remove           — interactive unblock"
        echo "  list             — show blocked apps"
        echo "  find \"name\"      — search bundle IDs"
        echo "  status           — daemon status"
        echo "  log              — show kill log"
        echo "  uninstall        — remove everything"
        echo ""
        ;;
esac
