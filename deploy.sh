#!/bin/bash
# ================================================================
#   VNET MOVIES - TELEGRAM BOT MANAGER
#   Install / Update / Rollback / Status / Uninstall  (Ubuntu VPS)
#
#   Usage:  sudo bash vnet_bot_manager.sh            (interactive menu)
#           sudo bash vnet_bot_manager.sh update     (install | update |
#                                                     rollback | status | uninstall)
# ================================================================
set -o pipefail

# ─────────────────────────────────────────────
#   CONFIGURATION
# ─────────────────────────────────────────────
BOT_SERVICE="vnet_movie_bot"
FOLDER="VNET_Movie_Bot"
GITHUB_REPO="VihanNethmira/vnetmoviebot"      # <-- ඔයාගේ Bot Repo එක
WORK_DIR="${WORK_DIR:-/root/$FOLDER}"
SERVICE_FILE="${SERVICE_DIR:-/etc/systemd/system}/${BOT_SERVICE}.service"
FINAL_BACKUP_DIR="${FINAL_BACKUP_DIR:-/root}"
KEEP_BACKUPS=5                                 # තබාගන්නා links.db backups ගණන

ENV_FILE="$WORK_DIR/.env"
BOT_FILE="$WORK_DIR/moviedatabase.py"
PREV_FILE="$WORK_DIR/moviedatabase.py.prev"
REL_FILE="$WORK_DIR/.release"
BACKUP_DIR="$WORK_DIR/backups"

# ─────────────────────────────────────────────
#   HELPERS
# ─────────────────────────────────────────────
confirm() { local a; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }

is_installed() { [ -f "$SERVICE_FILE" ] && [ -f "$BOT_FILE" ]; }

current_release() { [ -f "$REL_FILE" ] && cat "$REL_FILE" || echo "unknown"; }

mask() { if [ -z "$1" ]; then echo "none"; else echo "****${1: -6}"; fi; }

get_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

ask_tag() {
    local latest input prompt
    latest=$(get_latest_tag)
    if [ -n "$latest" ]; then prompt="Release tag [latest: $latest]"; else prompt="Release tag (e.g. v1.0.0)"; fi
    read -r -p "📂 $prompt: " input
    REL_TAG="${input:-$latest}"
    if [ -z "$REL_TAG" ]; then echo "❌ Release tag cannot be empty."; return 1; fi
}

# ask_value <label> <current> <regex> <hint> [display]
ask_value() {
    local input shown="${5:-${2:-none}}"
    while true; do
        read -r -p "  $1 [$shown]: " input
        input="${input:-$2}"
        input="${input// /}"
        if [[ "$input" =~ $3 ]]; then REPLY_VALUE="$input"; return 0; fi
        echo "  ⚠️ Invalid value. $4"
    done
}

load_env() {
    CUR_TOKEN=""; CUR_DB1=""; CUR_DB2=""; CUR_ADMINS=""
    if [ -f "$ENV_FILE" ]; then
        CUR_TOKEN=$(grep -oP '(?<=^API_TOKEN=).*' "$ENV_FILE" || true)
        CUR_DB1=$(grep -oP '(?<=^DB_CHANNEL_ID_1=).*' "$ENV_FILE" || true)
        CUR_DB2=$(grep -oP '(?<=^DB_CHANNEL_ID_2=).*' "$ENV_FILE" || true)
        CUR_ADMINS=$(grep -oP '(?<=^ADMIN_IDS=).*' "$ENV_FILE" || true)
    fi
}

ask_config() {
    load_env
    echo ""
    echo "── ⚙️ Bot Configuration (.env) ──"
    [ -f "$ENV_FILE" ] && echo " (Press Enter to keep the current value)"
    ask_value "🤖 Telegram Bot Token" "$CUR_TOKEN" '^[0-9]+:[A-Za-z0-9_-]+$' "Format: 123456789:ABCdef..." "$(mask "$CUR_TOKEN")"; API_TOKEN="$REPLY_VALUE"
    ask_value "📺 DB Channel ID 1" "$CUR_DB1" '^-?[0-9]+$' "Example: -1001234567890"; DB_CHANNEL_ID_1="$REPLY_VALUE"
    ask_value "📺 DB Channel ID 2" "$CUR_DB2" '^-?[0-9]+$' "Example: -1001234567890"; DB_CHANNEL_ID_2="$REPLY_VALUE"
    ask_value "👑 Admin IDs (comma separated)" "$CUR_ADMINS" '^[0-9]+(,[0-9]+)*$' "Example: 7165882908,1234567890"; ADMIN_IDS="$REPLY_VALUE"
}

write_env() {
    cat > "$ENV_FILE" <<EOF
API_TOKEN=$API_TOKEN
DB_CHANNEL_ID_1=$DB_CHANNEL_ID_1
DB_CHANNEL_ID_2=$DB_CHANNEL_ID_2
ADMIN_IDS=$ADMIN_IDS
EOF
    chmod 600 "$ENV_FILE"
    echo "✅ .env configuration written securely."
}

# download a release asset to <dest> and make sure it is valid Python
fetch_and_validate() {
    local tag="$1" dest="$2"
    local url="https://github.com/$GITHUB_REPO/releases/download/$tag/moviedatabase.py"
    echo "📥 Downloading: $url"
    if ! curl -fSL -o "$dest" "$url"; then
        echo "❌ Download failed. Check that release '$tag' is published and has an asset named exactly 'moviedatabase.py'."
        return 1
    fi
    if [ ! -s "$dest" ]; then echo "❌ Downloaded file is empty."; return 1; fi
    if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$dest" 2>/dev/null; then
        echo "❌ Downloaded file is not valid Python (syntax error). Aborting; nothing was changed."
        return 1
    fi
    echo "✅ Download verified."
}

setup_python() {
    if [ ! -x "$WORK_DIR/venv/bin/python" ]; then
        echo "🐍 Creating Python virtual environment..."
        apt-get update -qq && apt-get install -y -qq python3-pip python3-venv curl || { echo "❌ apt install failed."; return 1; }
        python3 -m venv "$WORK_DIR/venv" || { echo "❌ venv creation failed."; return 1; }
    fi
    "$WORK_DIR/venv/bin/pip" install -q --upgrade pyTelegramBotAPI python-dotenv || { echo "❌ pip install failed."; return 1; }
}

write_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=VNET Movie Telegram Bot - $1
After=network.target

[Service]
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/venv/bin/python moviedatabase.py
Restart=always
RestartSec=5
Environment="RELEASE=$1"

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

start_and_check() {
    systemctl restart "$BOT_SERVICE"
    sleep 4
    systemctl is-active --quiet "$BOT_SERVICE"
}

backup_db() {
    [ -f "$WORK_DIR/links.db" ] || return 0
    mkdir -p "$BACKUP_DIR"
    local f="$BACKUP_DIR/links.db.$(date +%Y%m%d-%H%M%S)"
    cp "$WORK_DIR/links.db" "$f" && echo "💾 Database backup: $f"
    # පරණ backups ඉවත් කරනවා (අලුත්ම $KEEP_BACKUPS පමණක් තබාගනී)
    ls -1t "$BACKUP_DIR"/links.db.* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm --
}

# swap current <-> previous version (used by rollback and failed-update recovery)
swap_versions() {
    local t a b
    t=$(mktemp)
    cp "$BOT_FILE" "$t" && mv "$PREV_FILE" "$BOT_FILE" && mv "$t" "$PREV_FILE" || return 1
    a=$(cat "$REL_FILE" 2>/dev/null || echo unknown)
    b=$(cat "$REL_FILE.prev" 2>/dev/null || echo unknown)
    echo "$b" > "$REL_FILE"
    echo "$a" > "$REL_FILE.prev"
    write_service "$b"
}

# ─────────────────────────────────────────────
#   ACTIONS
# ─────────────────────────────────────────────
do_install() {
    if is_installed; then
        echo "ℹ️ Already installed (release $(current_release)). Use 'Update' to change versions."
        return 1
    fi
    echo ""
    echo "── 📥 INSTALL ──"
    ask_tag || return 1
    ask_config

    mkdir -p "$WORK_DIR" "$BACKUP_DIR"
    local tmp; tmp=$(mktemp)
    fetch_and_validate "$REL_TAG" "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$BOT_FILE"

    write_env
    setup_python || return 1
    write_service "$REL_TAG"
    echo "$REL_TAG" > "$REL_FILE"
    systemctl enable "$BOT_SERVICE" >/dev/null 2>&1

    if start_and_check; then
        echo ""
        echo "🎉 SUCCESS: VNET Movie Bot ($REL_TAG) is live!"
        echo "   Logs: journalctl -u $BOT_SERVICE -n 20"
    else
        echo "⚠️ Service failed to start. Check: journalctl -u $BOT_SERVICE -n 50"
        return 1
    fi
}

do_update() {
    if ! is_installed; then echo "❌ Not installed yet. Choose 'Install' first."; return 1; fi
    echo ""
    echo "── 🔄 UPDATE ──   (current release: $(current_release))"
    ask_tag || return 1
    if [ "$REL_TAG" = "$(current_release)" ]; then
        confirm "Release $REL_TAG is already deployed. Re-deploy anyway?" || return 0
    fi

    # 1. කලින්ම download + validate කරනවා. Fail වුණොත් පරණ bot එක එහෙමම දුවනවා.
    local tmp; tmp=$(mktemp)
    fetch_and_validate "$REL_TAG" "$tmp" || { rm -f "$tmp"; return 1; }

    if confirm "Edit bot configuration (.env) as well?"; then
        ask_config
        write_env
    fi

    # 2. Stop -> backup -> swap
    echo "⏹  Stopping bot..."
    systemctl stop "$BOT_SERVICE" 2>/dev/null || true
    backup_db
    # දැනට දුවන version එක තාවකාලිකව save කරනවා. අලුත් එක සාර්ථක වුණාට පස්සේ පමණයි "previous" බවට පත් කරන්නේ.
    cp "$BOT_FILE" "$BOT_FILE.old"
    cp "$REL_FILE" "$REL_FILE.old" 2>/dev/null || echo "unknown" > "$REL_FILE.old"
    mv "$tmp" "$BOT_FILE"
    echo "$REL_TAG" > "$REL_FILE"

    setup_python || echo "⚠️ Dependency update failed, continuing with existing packages."
    write_service "$REL_TAG"

    # 3. Start. Fail වුණොත් auto-rollback
    if start_and_check; then
        mv "$BOT_FILE.old" "$PREV_FILE"
        mv "$REL_FILE.old" "$REL_FILE.prev"
        echo ""
        echo "🎉 Updated to $REL_TAG successfully. (Previous version kept for rollback.)"
    else
        echo "⚠️ New version failed to start. Rolling back automatically..."
        mv "$BOT_FILE.old" "$BOT_FILE"
        mv "$REL_FILE.old" "$REL_FILE"
        write_service "$(current_release)"
        if start_and_check; then
            echo "✅ Rolled back to $(current_release). Bot is running again."
            echo "   See what went wrong: journalctl -u $BOT_SERVICE -n 50"
        else
            echo "❌ Rollback also failed. Check: journalctl -u $BOT_SERVICE -n 50"
        fi
        return 1
    fi
}

do_rollback() {
    if ! is_installed; then echo "❌ Not installed."; return 1; fi
    if [ ! -f "$PREV_FILE" ]; then echo "❌ No previous version available to roll back to."; return 1; fi
    echo ""
    echo "── ⏪ ROLLBACK ──"
    echo "   Current : $(current_release)"
    echo "   Previous: $(cat "$REL_FILE.prev" 2>/dev/null || echo unknown)"
    confirm "Switch to the previous version?" || return 0

    systemctl stop "$BOT_SERVICE" 2>/dev/null || true
    backup_db
    swap_versions || { echo "❌ Could not swap files."; return 1; }
    if start_and_check; then
        echo "✅ Now running $(current_release). (Run Rollback again to switch back.)"
    else
        echo "⚠️ That version failed to start. Switching back..."
        if swap_versions && start_and_check; then
            echo "✅ Back on $(current_release), bot is running."
        else
            echo "❌ Could not recover. Check: journalctl -u $BOT_SERVICE -n 50"
        fi
        return 1
    fi
}

do_status() {
    echo ""
    echo "── 📊 STATUS ──"
    if ! is_installed; then
        echo "Bot: NOT installed"
        [ -d "$WORK_DIR" ] && echo "Leftover data folder exists: $WORK_DIR"
        return 0
    fi
    echo "Release  : $(current_release)"
    echo "Service  : $(systemctl is-active "$BOT_SERVICE" 2>/dev/null)  (enabled: $(systemctl is-enabled "$BOT_SERVICE" 2>/dev/null))"
    echo "Started  : $(systemctl show "$BOT_SERVICE" -p ActiveEnterTimestamp --value 2>/dev/null)"
    [ -f "$WORK_DIR/links.db" ] && echo "Database : $(du -h "$WORK_DIR/links.db" | cut -f1)  ($WORK_DIR/links.db)"
    echo "Backups  : $(ls -1 "$BACKUP_DIR"/links.db.* 2>/dev/null | wc -l) in $BACKUP_DIR"
    [ -f "$PREV_FILE" ] && echo "Rollback : available ($(cat "$REL_FILE.prev" 2>/dev/null || echo unknown))"
    echo ""
    echo "── Last 15 log lines ──"
    journalctl -u "$BOT_SERVICE" -n 15 --no-pager 2>/dev/null
}

do_uninstall() {
    if ! is_installed && [ ! -d "$WORK_DIR" ]; then echo "ℹ️ Nothing to uninstall."; return 0; fi
    echo ""
    echo "── 🗑  UNINSTALL ──"
    echo "   1) Remove the bot, KEEP data  (links.db, .env, backups stay in $WORK_DIR)"
    echo "   2) Remove EVERYTHING          (links.db = all movie links, .env, backups)"
    echo "   0) Cancel"
    local ch; read -r -p "Choose [0-2]: " ch

    case "$ch" in
        1) ;;
        2)
            local typed; read -r -p "⚠️ This deletes ALL bot data permanently. Type DELETE to confirm: " typed
            if [ "$typed" != "DELETE" ]; then echo "Cancelled."; return 0; fi
            if [ -f "$WORK_DIR/links.db" ] && confirm "Save a final copy of links.db to $FINAL_BACKUP_DIR first?"; then
                mkdir -p "$FINAL_BACKUP_DIR"
                local f="$FINAL_BACKUP_DIR/links.db.final-$(date +%Y%m%d-%H%M%S)"
                cp "$WORK_DIR/links.db" "$f" && echo "💾 Saved: $f"
            fi
            ;;
        *) echo "Cancelled."; return 0 ;;
    esac

    echo "⏹  Removing systemd service..."
    systemctl stop "$BOT_SERVICE" 2>/dev/null || true
    systemctl disable "$BOT_SERVICE" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl reset-failed "$BOT_SERVICE" 2>/dev/null || true

    if [ "$ch" = "1" ]; then
        rm -rf "$WORK_DIR/venv" "$WORK_DIR/__pycache__"
        rm -f "$BOT_FILE" "$PREV_FILE" "$REL_FILE" "$REL_FILE.prev"
        echo "✅ Bot removed. Your data is still in $WORK_DIR (links.db, .env, backups)."
        echo "   Installing again later will reuse it."
    else
        if [ -n "$WORK_DIR" ] && [ "$WORK_DIR" != "/" ]; then rm -rf "$WORK_DIR"; fi
        echo "✅ Everything removed."
    fi
}

# ─────────────────────────────────────────────
#   MAIN
# ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Please run as root:  sudo bash $0"
    exit 1
fi

case "${1:-}" in
    install)   do_install;   exit $? ;;
    update)    do_update;    exit $? ;;
    rollback)  do_rollback;  exit $? ;;
    status)    do_status;    exit $? ;;
    uninstall) do_uninstall; exit $? ;;
    "") ;;
    *) echo "Usage: $0 [install|update|rollback|status|uninstall]"; exit 1 ;;
esac

while true; do
    clear
    echo "================================================"
    echo "       VNET MOVIES - TELEGRAM BOT MANAGER       "
    echo "================================================"
    if is_installed; then
        echo " Status: ✅ Installed  (release: $(current_release))"
    else
        echo " Status: ⚪ Not installed"
    fi
    echo ""
    echo "  1) 📥 Install"
    echo "  2) 🔄 Update to a release"
    echo "  3) ⏪ Rollback to previous version"
    echo "  4) 📊 Status & logs"
    echo "  5) 🗑  Uninstall"
    echo "  0) Exit"
    echo ""
    read -r -p "Choose an option: " CHOICE
    case "$CHOICE" in
        1) do_install ;;
        2) do_update ;;
        3) do_rollback ;;
        4) do_status ;;
        5) do_uninstall ;;
        0) echo "Bye!"; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
    echo ""
    read -r -p "Press Enter to continue..."
done
