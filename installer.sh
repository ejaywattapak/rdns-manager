#!/usr/bin/env bash
#
# EJVPN RDNS — launcher installer
# Installer ini menjalankan setup.sh.
#
set -e

if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec bash "$SCRIPT_DIR/setup.sh" "$@"
