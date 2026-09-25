#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_DIR="/usr/local/share/ejvpn-rdns"
SOURCE="$BASE_DIR/rdns-menu.sh"
MENU="$BASE_DIR/menu.sh"

clear
printf '\033[1;36m'
cat <<'EOF'
 ______     _ ____   _   _ ____  
| ____|_  _| |  _ \ / \ | / ___| 
|  _| \ \/ / | |_) / _ \| \___ \ 
| |___ >  <| |  _ < ___ \___) |
|_____/_/\_\_|_| \_\_/ \_\____/ 
EOF
printf '\033[0m\n'
echo "==================="
echo "Sila pilih menu option:"
echo ""
echo "1. Install RDNS Manager"
echo "2. Exit"
echo ""

read -rp "Pilih menu: " ch

case "$ch" in
  1)
    mkdir -p "$BASE_DIR"
    cp "$SCRIPT_DIR/rdns-menu.sh" "$SOURCE"
    cp "$SCRIPT_DIR/menu.sh" "$MENU"
    chmod +x "$SOURCE" "$MENU"

    echo ""
    echo "==> Memulakan Setup / Install..."
    echo ""

    # Ambil definisi fungsi asal sahaja, tanpa menjalankan main menu.
    # $0 ditetapkan kepada menu.sh supaya cron asal menunjuk ke fail
    # menu.sh yang kekal di BASE_DIR.
    bash -c '
      source <(sed "/^# ---------- Mod cron (tanpa menu) ----------/q" "$1")
      initial_setup
    ' "$MENU" "$SOURCE"

    echo ""
    echo "==> Setup selesai."
    sleep 1
    exec bash "$MENU"
    ;;
  2)
    exit 0
    ;;
  *)
    echo "Pilihan tak sah."
    exit 1
    ;;
esac
