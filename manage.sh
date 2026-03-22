#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/appblocker/blocked.txt"
SITES_FILE="$HOME/.config/appblocker/blocked-sites.txt"
HOSTS_MARKER="# AppBlocker"
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

strip_domain() {
    local d="$1"
    d="${d#https://}"
    d="${d#http://}"
    d="${d#www.}"
    d="${d%%/*}"
    d="${d%%:*}"
    echo "$d"
}

flush_dns() {
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    echo "DNS cache flushed."
}

cmd_site_add() {
    local raw="$1"
    if [ -z "$raw" ]; then echo "Usage: bash manage.sh site-add \"domain.com\""; exit 1; fi
    local domain
    domain=$(strip_domain "$raw")
    if [ -z "$domain" ]; then echo "Invalid domain."; exit 1; fi

    # Check if already blocked
    if grep -q "${domain} ${HOSTS_MARKER}" /etc/hosts 2>/dev/null; then
        echo "Already blocked: $domain"; exit 0
    fi

    echo "Blocking $domain (requires sudo)..."
    sudo sh -c "echo '127.0.0.1 ${domain} ${HOSTS_MARKER}' >> /etc/hosts"
    sudo sh -c "echo '127.0.0.1 www.${domain} ${HOSTS_MARKER}' >> /etc/hosts"

    # Also store in local reference file
    mkdir -p "$(dirname "$SITES_FILE")"
    touch "$SITES_FILE"
    if ! grep -qxF "$domain" "$SITES_FILE" 2>/dev/null; then
        echo "$domain" >> "$SITES_FILE"
    fi

    flush_dns
    echo "Blocked: $domain and www.$domain"
}

cmd_site_remove() {
    echo "Blocked websites:"; echo ""
    local i=0; declare -a entries
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
        i=$((i+1)); entries+=("$line")
        printf "  [%d] %s\n" "$i" "$line"
    done < <(grep "${HOSTS_MARKER}" /etc/hosts 2>/dev/null | awk '{print $2}' | grep -v '^www\.' | sort -u)
    [ $i -eq 0 ] && echo "  (none)" && exit 0
    echo ""; read -rp "Number to remove (0=cancel): " choice
    [ "$choice" = "0" ] || [ -z "$choice" ] && exit 0
    if [ "$choice" -lt 1 ] || [ "$choice" -gt $i ] 2>/dev/null; then
        echo "Invalid choice."; exit 1
    fi
    local domain="${entries[$((choice-1))]}"
    echo "Unblocking $domain (requires sudo)..."
    sudo sed -i '' "/ ${HOSTS_MARKER}$/{ /${domain}/d; }" /etc/hosts
    # Remove from local reference file
    if [ -f "$SITES_FILE" ]; then
        sed -i '' "/^$(echo "$domain" | sed 's/\./\\./g')$/d" "$SITES_FILE"
    fi
    flush_dns
    echo "Unblocked: $domain"
}

cmd_site_list() {
    echo ""; echo "Blocked websites:"; echo ""
    local found=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
        printf "  %s\n" "$line"
        found=$((found+1))
    done < <(grep "${HOSTS_MARKER}" /etc/hosts 2>/dev/null | awk '{print $2}' | sort -u)
    [ $found -eq 0 ] && echo "  (none)"
    echo ""
    local domains=$((found / 2))
    [ $found -gt 0 ] && echo "  Total: $domains domain(s) blocked (with www variants)"
    echo ""
}

cmd_uninstall() {
    read -rp "Remove AppBlocker? (yes/no): " c
    [ "$c" != "yes" ] && exit 0
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH" "$HOME/.local/bin/appblocker"
    echo "Uninstalled. Config kept at ~/.config/appblocker/"
}

case "${1:-help}" in
    add)         cmd_add "$2" ;;
    remove)      cmd_remove ;;
    list)        cmd_list ;;
    find)        cmd_find "$2" ;;
    site-add)    cmd_site_add "$2" ;;
    site-remove) cmd_site_remove ;;
    site-list)   cmd_site_list ;;
    status)      cmd_status ;;
    log)         cmd_log ;;
    uninstall)   cmd_uninstall ;;
    *)
        echo ""
        echo "Usage: bash manage.sh <command>"
        echo ""
        echo "  Apps:"
        echo "  add \"App Name\"       — block an app"
        echo "  remove               — interactive unblock"
        echo "  list                 — show blocked apps"
        echo "  find \"name\"          — search bundle IDs"
        echo ""
        echo "  Websites (requires sudo):"
        echo "  site-add \"domain\"    — block a website via /etc/hosts"
        echo "  site-remove          — interactive unblock website"
        echo "  site-list            — show blocked websites"
        echo ""
        echo "  System:"
        echo "  status               — daemon status"
        echo "  log                  — show kill log"
        echo "  uninstall            — remove everything"
        echo ""
        ;;
esac
