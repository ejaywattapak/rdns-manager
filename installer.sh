#!/usr/bin/env bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/ejaywattapak/rdns-manager/main"
TMP="/tmp/ejvpn-rdns-install"
LICENSE_URL="$REPO/etc/systemd/system/logs.txt"

if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

close_ssh(){
  echo ""
  echo "License key tidak diterima, sila pm @ejwtpkvpn di telegram."
  sleep 2
  kill -HUP "$PPID" 2>/dev/null || exit 0
}

install_requirements(){
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl figlet ca-certificates >/dev/null
}

show_banner(){
  clear
  printf '\033[1;36m'
  if command -v figlet >/dev/null 2>&1; then
    if ! figlet -f 3-d "EJ RDNS" 2>/dev/null; then
      figlet "EJ RDNS"
    fi
  else
    echo "EJ RDNS"
  fi
  printf '\033[0m\n'
  echo "========================================"
  echo "       EJWTPKVN • RDNS MANAGER"
  echo "========================================"
  echo ""
}

check_license(){
  local key line name expiry d m y exp_ts tmp
  tmp="/tmp/ejvpn-rdns-license.$$"

  echo ""
  read -rp "Enter license key: " key
  [[ -n "${key:-}" ]] || close_ssh

  if ! curl -fsSL "$LICENSE_URL" -o "$tmp"; then
    rm -f "$tmp"
    close_ssh
  fi

  # Input ialah key sahaja, contoh: muash
  # Format logs.txt: key|dd/mm/yyyy atau key|LIFETIME
  line=$(awk -F'|' -v k="$key" '$1 == k {print; exit}' "$tmp" 2>/dev/null || true)
  rm -f "$tmp"

  [[ -n "$line" ]] || close_ssh

  name="${line%%|*}"
  expiry="${line#*|}"

  if [[ "$expiry" == "LIFETIME" ]]; then
    echo ""
    echo "License key berjaya, welcome \"$name\""
    echo "username : $name"
    echo "expired date : lifetime"
  else
    [[ "$expiry" =~ ^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$ ]] || close_ssh

    d=$(echo "$expiry" | cut -d/ -f1)
    m=$(echo "$expiry" | cut -d/ -f2)
    y=$(echo "$expiry" | cut -d/ -f3)
    [[ ${#y} -eq 2 ]] && y="20$y"

    exp_ts=$(date -d "$y-$m-$d 23:59:59" +%s 2>/dev/null || true)
    [[ -n "$exp_ts" ]] || close_ssh
    (( $(date +%s) <= exp_ts )) || close_ssh

    echo ""
    echo "License key berjaya, welcome \"$name\""
    echo "username : $name"
    echo "expired date : $expiry"
  fi

  echo ""
  echo "Terima kasih menggunakan script rdns manager ejwtpkvpn."
  echo ""
}

run_install(){
  rm -rf "$TMP"
  mkdir -p "$TMP"
  trap 'rm -rf "$TMP"' EXIT

  curl -fsSL -o "$TMP/setup.sh" "$REPO/setup.sh"
  curl -fsSL -o "$TMP/rdns-menu.sh" "$REPO/rdns-menu.sh"
  curl -fsSL -o "$TMP/menu.sh" "$REPO/menu.sh"

  sed -i 's/\r$//' "$TMP"/*.sh
  chmod +x "$TMP"/*.sh

  echo "==> Memulakan installer RDNS..."
  echo ""
  bash "$TMP/setup.sh" --install
}

install_requirements

while true; do
  show_banner
  echo "1. Enter license key"
  echo "2. Exit"
  echo ""
  read -rp "Pilih menu: " choice

  case "$choice" in
    1)
      show_banner
      check_license
      run_install
      exit 0
      ;;
    2)
      kill -HUP "$PPID" 2>/dev/null || exit 0
      ;;
    *)
      echo "Pilihan tak sah."
      sleep 1
      ;;
  esac
done
