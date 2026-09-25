#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_DIR="/usr/local/share/ejvpn-rdns"
SOURCE="$BASE_DIR/rdns-menu.sh"
MENU="$BASE_DIR/menu.sh"

[[ "${1:-}" == "--install" ]] || {
  echo "Gunakan installer.sh untuk pemasangan."
  exit 1
}

mkdir -p "$BASE_DIR"
cp "$SCRIPT_DIR/rdns-menu.sh" "$SOURCE"
cp "$SCRIPT_DIR/menu.sh" "$MENU"
chmod +x "$SOURCE" "$MENU"

# Jalankan fungsi initial_setup asal sahaja tanpa main loop.
bash -c '
  source <(sed "/^# ---------- Mod cron (tanpa menu) ----------/q" "$1")
  initial_setup
' "$MENU" "$SOURCE"

# Auto buka menu setiap root login SSH.
BASHRC="/root/.bashrc"
MARKER="# EJVPN-RDNS-AUTO-MENU"

if ! grep -Fq "$MARKER" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_EOF'

# EJVPN-RDNS-AUTO-MENU
if [[ $- == *i* ]] && [[ -x /usr/local/share/ejvpn-rdns/menu.sh ]]; then
  bash /usr/local/share/ejvpn-rdns/menu.sh
fi
BASHRC_EOF
fi

exec bash "$MENU"
