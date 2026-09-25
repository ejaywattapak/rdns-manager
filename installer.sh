#!/usr/bin/env bash
set -e

REPO="https://raw.githubusercontent.com/ejaywattapak/rdns-manager/main"
TMP="/tmp/ejvpn-rdns-install"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

command -v wget >/dev/null 2>&1 || {
  apt-get update -qq
  apt-get install -y -qq wget
}

wget -q -O "$TMP/setup.sh" "$REPO/setup.sh"
wget -q -O "$TMP/rdns-menu.sh" "$REPO/rdns-menu.sh"
wget -q -O "$TMP/menu.sh" "$REPO/menu.sh"

sed -i -e 's/\r$//' "$TMP"/*.sh
chmod +x "$TMP"/*.sh

exec bash "$TMP/setup.sh"
