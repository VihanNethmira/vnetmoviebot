#!/bin/bash
set -e

# ─────────────────────────────────────────────
#   CONFIGURATION
# ─────────────────────────────────────────────
BOT_SERVICE="vnet_movie_bot"
FOLDER="VNET_Movie_Bot"
WORK_DIR="/root/$FOLDER"
ENV_FILE="$WORK_DIR/.env"
GITHUB_REPO="VihanNethmira/vnetmoviebot" # <-- ඔයාගේ Bot එක තියෙන Repo එක මෙතනට දාන්න

clear
echo "================================================"
echo "    VNET MOVIES - TELEGRAM BOT DEPLOYMENT TOOL  "
echo "    Side-by-side execution setup for Ubuntu VPS "
echo "================================================"
echo ""

# 1. Ask for Release Version Tag
read -p "📂 Enter GitHub Release Tag to deploy (e.g., v1.0.0): " REL_TAG
if [ -z "$REL_TAG" ]; then
    echo "❌ ERROR: Release tag cannot be empty."
    exit 1
fi

# 2. Collect Configuration Details Dynamically
echo ""
echo "── ⚙️ Enter Bot Configurations (.env details) ──"

# කලින් විස්තර තිබ්බා නම් ඒවා default පෙන්නන්න කියවනවා
if [ -f "$ENV_FILE" ]; then
    CUR_TOKEN=$(grep -oP '(?<=^API_TOKEN=).*' "$ENV_FILE" || true)
    CUR_DB1=$(grep -oP '(?<=^DB_CHANNEL_ID_1=).*' "$ENV_FILE" || true)
    CUR_DB2=$(grep -oP '(?<=^DB_CHANNEL_ID_2=).*' "$ENV_FILE" || true)
    CUR_ADMINS=$(grep -oP '(?<=^ADMIN_IDS=).*' "$ENV_FILE" || true)
    echo " (Press Enter to keep current configuration)"
fi

read -p "  🤖 Telegram Bot Token [${CUR_TOKEN:-none}]: " IN_TOKEN
read -p "  📺 DB Channel ID 1 [${CUR_DB1:-none}]: " IN_DB1
read -p "  📺 DB Channel ID 2 [${CUR_DB2:-none}]: " IN_DB2
read -p "  👑 Admin IDs (comma separated) [${CUR_ADMINS:-none}]: " IN_ADMINS

API_TOKEN="${IN_TOKEN:-$CUR_TOKEN}"
DB_CHANNEL_ID_1="${IN_DB1:-$CUR_DB1}"
DB_CHANNEL_ID_2="${IN_DB2:-$CUR_DB2}"
ADMIN_IDS="${IN_ADMINS:-$CUR_ADMINS}"

# 3. Setup Directories
echo ""
echo "⏳ Preparing deployment folders..."
mkdir -p "$WORK_DIR"

# 4. Download Raw Python File directly from GitHub Release Asset
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$REL_TAG/moviedatabase.py"
echo "📥 Downloading raw asset from: $DOWNLOAD_URL"

# කලින් service එක දුවනවා නම් නවත්තනවා ෆයිල් එක මාරු කරන්න කලින්
sudo systemctl stop "$BOT_SERVICE" 2>/dev/null || true

# Wget එකෙන් කෙලින්ම .py එක බානවා
if ! curl -fsSL -L -o "$WORK_DIR/moviedatabase.py" "$DOWNLOAD_URL"; then
    echo "❌ ERROR: Failed to download moviedatabase.py from the release asset."
    echo "Please check if the file name matches exactly and release is published."
    exit 1
fi

# 5. Write the Secure .env file inside VPS
cat <<EOF > "$ENV_FILE"
API_TOKEN=$API_TOKEN
DB_CHANNEL_ID_1=$DB_CHANNEL_ID_1
DB_CHANNEL_ID_2=$DB_CHANNEL_ID_2
ADMIN_IDS=$ADMIN_IDS
EOF
chmod 600 "$ENV_FILE"
echo "✅ .env configuration file written securely."

# 6. Setup Python Environments & Dependencies
echo "🐍 Setting up Python Virtual Environment..."
sudo apt-get update -qq && sudo apt-get install -y python3-pip python3-venv curl -y
python3 -m venv "$WORK_DIR/venv"
source "$WORK_DIR/venv/bin/activate"
pip install -q pyTelegramBotAPI python-dotenv
deactivate

# 7. Create Background Linux Systemd Service
echo "🛠️ Creating systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/${BOT_SERVICE}.service > /dev/null
[Unit]
Description=VNET Movie Telegram Bot - $REL_TAG
After=network.target

[Service]
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/venv/bin/python moviedatabase.py
Restart=always
RestartSec=5
Environment="RELEASE=$REL_TAG"

[Install]
WantedBy=multi-user.target
EOF

# 8. Start & Enable everything
sudo systemctl daemon-reload
sudo systemctl enable "$BOT_SERVICE"
sudo systemctl restart "$BOT_SERVICE"

sleep 2
echo ""
echo "================================================"
if sudo systemctl is-active --quiet "$BOT_SERVICE"; then
    echo " 🎉 SUCCESS: VNET Movie Bot ($REL_TAG) is Live!"
    echo " Status: Running in background via systemd."
    echo " Use 'journalctl -u $BOT_SERVICE -n 20' to check logs."
else
    echo " ⚠️ WARNING: Bot service failed to start properly."
    echo " Run: journalctl -u $BOT_SERVICE -n 50"
fi
echo "================================================"