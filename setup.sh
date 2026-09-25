#!/usr/bin/env bash
set -uo pipefail

C="\033[1;36m"; G="\033[1;32m"; R="\033[1;31m"; N="\033[0m"

if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

BASE_DIR="/usr/local/share/ejvpn-rdns"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SOURCE="$BASE_DIR/rdns-menu.sh"
MENU="$BASE_DIR/menu.sh"

clear
echo -e "${C}"
cat <<'EOF'
███████      ██    ██ ██████  ███    ██
██           ██    ██ ██   ██ ████   ██
█████        ██    ██ ██████  ██ ██  ██
██           ██    ██ ██   ██ ██  ██ ██
██            ██████  ██   ██ ██   ████

██████   ██████  ███    ██ ███████
██   ██ ██    ██ ████   ██ ██
██████  ██    ██ ██ ██  ██ ███████
██      ██    ██ ██  ██ ██      ██
██       ██████  ██   ████ ███████
EOF
echo -e "${N}"
echo -e "${C}===================${N}"
echo -e "${C}Sila pilih menu option:${N}"
echo ""
echo -e "${G}1. Install RDNS Manager${N}"
echo -e "${R}2. Exit${N}"
echo ""

read -rp "Pilih [1-2]: " CH

case "$CH" in
  1)
    mkdir -p "$BASE_DIR"
    echo -e "${C}==> Memasang RDNS Manager...${N}"

    mkdir -p "$BASE_DIR"
    cp "$SCRIPT_DIR/rdns-menu.sh" "$SOURCE"
    cp "$SCRIPT_DIR/menu.sh" "$MENU"
    chmod +x "$SOURCE" "$MENU"

    # rdns-menu.sh ialah sumber asal. Pilihan 9 asal = initial_setup.
    if [[ ! -f "$SOURCE" ]]; then
      echo -e "${R}rdns-menu.sh tidak dijumpai.${N}"
      exit 1
    fi

    chmod +x "$SOURCE" "$MENU" 2>/dev/null || true
    source "$SOURCE"

    # Jalankan tepat fungsi yang dipanggil oleh pilihan 9 asal.
    initial_setup

    echo -e "${G}✓ RDNS Manager selesai dipasang.${N}"
    exec bash "$MENU"
    ;;
  2)
    exit 0
    ;;
  *)
    echo -e "${R}Pilihan tak sah.${N}"
    exit 1
    ;;
esac
