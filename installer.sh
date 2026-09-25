#!/usr/bin/env bash
set -e

REPO="https://raw.githubusercontent.com/ejaywattapak/rdns-manager/main"
TMP="/tmp/ejvpn-rdns-install"

mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq curl
fi

curl -fsSL -o "$TMP/setup.sh" "$REPO/setup.sh"
curl -fsSL -o "$TMP/rdns-menu.sh" "$REPO/rdns-menu.sh"
curl -fsSL -o "$TMP/menu.sh" "$REPO/menu.sh"

sed -i 's/\r$//' "$TMP"/*.sh
chmod +x "$TMP"/*.sh

exec bash "$TMP/setup.sh"
