#!/usr/bin/env bash
#
# EJVPN RDNS — installer setup
# Pilihan 1 menjalankan installer asal dari pilihan 9 rdns-menu.sh.
#
set -uo pipefail

C="\033[1;36m"; G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; N="\033[0m"

pause(){ echo ""; read -rp "Tekan [Enter] untuk sambung..."; }

# ---------- Auto-sudo ----------
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi

INSTALL_DIR="/usr/local/bin"
PERSIST_SETUP="$INSTALL_DIR/rdns-setup.sh"
PERSIST_MENU="$INSTALL_DIR/menu.sh"
SELF="$(readlink -f "$0")"

# Pasang salinan kekal supaya cron tidak bergantung pada folder ZIP.
mkdir -p "$INSTALL_DIR"
if [[ "$SELF" != "$PERSIST_SETUP" ]]; then
  cp "$SELF" "$PERSIST_SETUP"
fi
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
if [[ -f "$SCRIPT_DIR/menu.sh" && "$(readlink -f "$SCRIPT_DIR/menu.sh")" != "$PERSIST_MENU" ]]; then
  cp "$SCRIPT_DIR/menu.sh" "$PERSIST_MENU"
fi
chmod +x "$PERSIST_SETUP" "$PERSIST_MENU" 2>/dev/null || true

# Bila dipanggil oleh cron, serahkan kerja statistik/expired/kuota
# kepada menu.sh yang mengandungi handler --bw-save asal.
if [[ "${1:-}" == "--bw-save" ]]; then
  exec bash "$PERSIST_MENU" --bw-save
fi

# Pastikan setup berjalan dari salinan kekal.
if [[ "$SELF" != "$PERSIST_SETUP" ]]; then
  exec bash "$PERSIST_SETUP" "$@"
fi

clear
echo -e "${C}"
cat <<'EOF'
#####  #####  #   #  ####   #   #
#          #  #   #  #   #  ##  #
####       #  #   #  ####   # # #
#      #   #   # #   #      #  ##
#####   ###     #    #      #   #

####   ####   #   #   ####
#   #  #   #  ##  #  #
####   #   #  # # #   ###
#  #   #   #  #  ##      #
#   #  ####   #   #  ####
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
    clear
# ---------- Pasang keperluan ----------
ensure_deps(){
  local need=0
  for b in curl openssl jq cron; do command -v "$b" >/dev/null 2>&1 || need=1; done
  if [[ $need -eq 1 ]]; then
    echo -e "${Y}==> Memasang keperluan (curl, openssl, jq, cron)...${N}"
    apt update -y && apt install -y curl openssl jq iptables cron
  fi
}

xray_installed(){ [[ -x "$XRAY_BIN" ]]; }

# ---------- Install Xray + config asas + servis ----------
initial_setup(){
  ensure_deps
  if ! xray_installed; then
    echo -e "${Y}==> Install Xray...${N}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  else
    echo -e "${G}Xray sudah dipasang: $($XRAY_BIN version | head -n1)${N}"
  fi

  mkdir -p /usr/local/etc/xray /var/log/xray
  touch /var/log/xray/socks-access.log /var/log/xray/socks-error.log

  local port="$SOCKS_PORT_DEFAULT"
  read -rp "Port SOCKS5 [${SOCKS_PORT_DEFAULT}]: " p; [[ -n "${p:-}" ]] && port="$p"

  if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${Y}Config sedia ada dijumpai — kekalkan user sedia ada.${N}"
  else
    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "access": "/var/log/xray/socks-access.log",
    "error": "/var/log/xray/socks-error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [],
        "udp": true
      },
      "tag": "socks-in"
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["10.0.0.0/8","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.168.0.0/16","::1/128","fc00::/7","fe80::/10"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
    echo -e "${G}Config asas dicipta.${N}"
  fi

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray SOCKS5 Server
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=${XRAY_BIN} run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now xray-socks >/dev/null 2>&1

  open_firewall "$port"
  ensure_bw_rules "$port"
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
  bw_install_cron
  bw_save
  restart_service
  echo -e "${G}✅ Setup asas selesai. Sekarang tambah user dari menu (pilihan 1).${N}"
  pause
}
# ---------- Firewall ----------
open_firewall(){
  local port="$1"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${port}/tcp" >/dev/null 2>&1
    echo -e "${G}Firewall (UFW): port ${port}/tcp dibuka.${N}"
  else
    local pos
    pos=$(iptables -L INPUT --line-numbers -n 2>/dev/null | awk '/ufw-/{print $1; exit}')
    if [[ -n "${pos:-}" ]]; then
      iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT "$pos" -p tcp --dport "$port" -j ACCEPT
    else
      iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
    fi
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
    echo -e "${G}Firewall (iptables): port ${port}/tcp dibuka.${N}"
  fi
}
get_port(){ jq -r '.inbounds[0].port' "$CONFIG_FILE"; }

apply(){ # test + restart
  if "$XRAY_BIN" -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
    systemctl restart xray-socks
    echo -e "${G}✅ Diguna & servis di-restart.${N}"
  else
    echo -e "${R}❌ Config tak sah! Perubahan tak diguna. Semak:${N}"
    "$XRAY_BIN" -test -config "$CONFIG_FILE"
  fi
}

restart_service(){ systemctl restart xray-socks 2>/dev/null && echo -e "${G}Servis di-restart.${N}" || echo -e "${R}Gagal restart.${N}"; }

# ================= BANDWIDTH (kiraan per-port + statistik kekal + kuota) =================
hr() { # tukar bytes -> B/KB/MB/GB/TB
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    printf "%.2f %s", b, u[i]
  }'
}

hr() { # tukar bytes -> B/KB/MB/GB/TB
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    printf "%.2f %s", b, u[i]
  }'
}

ensure_bw_rules() { # cipta chain + rule kiraan untuk port SOCKS
  local port="$1" proto
  [[ -z "${port:-}" || "$port" == "null" ]] && return
  iptables -N SOCKS_BW_IN  2>/dev/null || true
  iptables -N SOCKS_BW_OUT 2>/dev/null || true
  iptables -C SOCKS_BW_IN  -j RETURN 2>/dev/null || iptables -A SOCKS_BW_IN  -j RETURN
  iptables -C SOCKS_BW_OUT -j RETURN 2>/dev/null || iptables -A SOCKS_BW_OUT -j RETURN
  for proto in tcp udp; do
    iptables -C INPUT  -p "$proto" --dport "$port" -j SOCKS_BW_IN  2>/dev/null || \
      iptables -I INPUT  -p "$proto" --dport "$port" -j SOCKS_BW_IN
    iptables -C OUTPUT -p "$proto" --sport "$port" -j SOCKS_BW_OUT 2>/dev/null || \
      iptables -I OUTPUT -p "$proto" --sport "$port" -j SOCKS_BW_OUT
  done
}

get_bw_bytes() { # $1 = nama chain -> bytes
  iptables -L "$1" -v -n -x 2>/dev/null | awk 'NR==3 {print $2}'
}

bw_write_state() { # tulis state (ambil nilai dari pembolehubah fungsi pemanggil)
  cat > "$BW_STATE" <<EOF
last_in=${last_in:-0}
last_out=${last_out:-0}
total_in=${total_in:-0}
total_out=${total_out:-0}
month=${month:-}
month_in=${month_in:-0}
month_out=${month_out:-0}
quota_gb=${quota_gb:-0}
enforce_mode=${enforce_mode:-none}
quota_blocked=${quota_blocked:-0}
EOF
}

bw_save() { # baca counter iptables, tambah delta ke fail state
  local port in_b out_b
  port=$(get_port 2>/dev/null)
  [[ -z "${port:-}" || "$port" == "null" ]] && return
  ensure_bw_rules "$port"
  in_b=$(get_bw_bytes SOCKS_BW_IN);   in_b=${in_b:-0}
  out_b=$(get_bw_bytes SOCKS_BW_OUT); out_b=${out_b:-0}
  mkdir -p "$BW_DIR"; chmod 700 "$BW_DIR"
  local last_in=0 last_out=0 total_in=0 total_out=0 month="" month_in=0 month_out=0 quota_gb=0 enforce_mode="none" quota_blocked=0
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  local cur_month; cur_month=$(date +%Y-%m)
  if [[ "$month" != "$cur_month" ]]; then month="$cur_month"; month_in=0; month_out=0; fi
  local d_in d_out
  if (( in_b >= last_in ));  then d_in=$((in_b - last_in));    else d_in=$in_b;   fi
  if (( out_b >= last_out )); then d_out=$((out_b - last_out)); else d_out=$out_b; fi
  total_in=$((total_in + d_in));   total_out=$((total_out + d_out))
  month_in=$((month_in + d_in));   month_out=$((month_out + d_out))
  bw_write_state
}

bw_enforce() { # kuatkuasa kuota — idempotent, selamat dipanggil berulang kali
  local last_in=0 last_out=0 total_in=0 total_out=0 month="" month_in=0 month_out=0 quota_gb=0 enforce_mode="none" quota_blocked=0
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  (( quota_gb > 0 )) || return
  [[ "$enforce_mode" == "stop" || "$enforce_mode" == "block" ]] || return
  local port m limit
  port=$(get_port 2>/dev/null)
  m=$((month_in + month_out))
  limit=$((quota_gb * 1073741824))
  if (( m >= limit )); then
    if [[ "$enforce_mode" == "stop" ]]; then
      systemctl stop xray-socks 2>/dev/null
    elif [[ -n "${port:-}" && "$port" != "null" ]]; then
      iptables -C INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || iptables -I INPUT 1 -p tcp --dport "$port" -j DROP
      iptables -C INPUT -p udp --dport "$port" -j DROP 2>/dev/null || iptables -I INPUT 1 -p udp --dport "$port" -j DROP
    fi
    if [[ "$quota_blocked" != "1" ]]; then
      quota_blocked=1
      logger -t socks-bw "Kuota ${quota_gb}GB dicapai — akses disekat (mod: ${enforce_mode})." 2>/dev/null || true
      bw_write_state
    fi
  elif [[ "$quota_blocked" == "1" ]]; then
    if [[ "$enforce_mode" == "stop" ]]; then
      systemctl start xray-socks 2>/dev/null
    elif [[ -n "${port:-}" && "$port" != "null" ]]; then
      iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
      iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null || true
    fi
    quota_blocked=0
    logger -t socks-bw "Bawah had semula — sekatan dibuka (mod: ${enforce_mode})." 2>/dev/null || true
    bw_write_state
  fi
}

get_bandwidth() { # paparan live (sejak reboot)
  local port rx tx
  port=$(get_port 2>/dev/null)
  [[ -z "${port:-}" || "$port" == "null" ]] && { echo "N/A"; return; }
  bw_save
  rx=$(get_bw_bytes SOCKS_BW_IN);  rx=${rx:-0}
  tx=$(get_bw_bytes SOCKS_BW_OUT); tx=${tx:-0}
  echo -e "${G}↓ $(hr "$tx")${N}  ${Y}↑ $(hr "$rx")${N}"
}

get_bandwidth_persist() { # Bulan ini | Keseluruhan + status kuota/sekatan
  local total_in=0 total_out=0 month_in=0 month_out=0 quota_gb=0 enforce_mode="none" quota_blocked=0
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  local m=$((month_in + month_out))
  echo -e "${C}Bulan ini: $(hr "$m")${N}  |  ${G}Keseluruhan: $(hr $((total_in + total_out)))${N}"
  if (( quota_gb > 0 )); then
    local pct=$(( m * 100 / (quota_gb * 1073741824) ))
    local col="$G" extra=""
    if   (( pct >= 100 )); then col="$R"; extra="  ⚠ MELEBIHI KUOTA!"
    elif (( pct >= 80 ));  then col="$Y"; extra="  ⚠ Hampir had!"
    fi
    echo -e "                 ${col}Kuota: $(hr "$m") / ${quota_gb} GB (${pct}%)${extra}${N}"
    [[ "$quota_blocked" == "1" ]] && \
      echo -e "                 ${R}⛔ AKSES DISEKAT (mod: ${enforce_mode}) — pulih automatik bila bulan baru.${N}"
  fi
}

bw_install_cron() { # pasang cron setiap 5 minit
  local self; self=$(readlink -f "$0")
  cat > /etc/cron.d/socks-bw <<EOF
# Simpan bacaan bandwidth SOCKS setiap 5 minit + semak expired + kuatkuasa kuota
*/5 * * * * root bash "$self" --bw-save >/dev/null 2>&1
EOF
  echo -e "${G}Cron dipasang (/etc/cron.d/socks-bw)${N}"
}
    echo -e "${G}✅ Install RDNS Manager selesai.${N}"
    echo ""
    read -rp "Tekan [Enter] untuk buka menu RDNS..." _
    exec bash "$PERSIST_MENU"
    ;;
  2)
    exit 0
    ;;
  *)
    echo -e "${R}Pilihan tak sah.${N}"
    sleep 1
    exit 1
    ;;
esac
