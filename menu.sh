#!/usr/bin/env bash
#
# socks-manager.sh — Menu interaktif untuk urus Xray SOCKS5 server
# Ciri  : urus user (tambah/buang/password), expired & renew user,
#         kiraan bandwidth per-port (iptables), statistik kekal (cron),
#         kuota bulanan + tindakan auto (stop servis / blok port).
# Guna  : sudo bash socks-manager.sh
#
set -uo pipefail

CONFIG_FILE="/usr/local/etc/xray/socks.json"
SERVICE_FILE="/etc/systemd/system/xray-socks.service"
XRAY_BIN="/usr/local/bin/xray"
SOCKS_PORT_DEFAULT="1080"

BW_DIR="/var/lib/socks-bw"
BW_STATE="$BW_DIR/state"
EXP_FILE="$BW_DIR/expiry.json"

# ---------- Warna ----------
G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

# ---------- Auto-sudo (taip 'socks' sahaja pun jadi) ----------
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$(readlink -f "$0")" "$@"
fi
pause(){ echo ""; read -rp "Tekan [Enter] untuk sambung..."; }

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

need_config(){
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${R}Config belum wujud. Jalankan installer RDNS Manager dulu.${N}"; pause; return 1
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

set_quota() { # set / buang had kuota bulanan
  need_config || return
  bw_save
  local quota_gb=0 q
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  if (( quota_gb > 0 )); then
    echo -e "${C}Had kuota bulanan sekarang: ${Y}${quota_gb} GB${N}"
  else
    echo -e "${C}Had kuota bulanan sekarang: ${N}TIADA"
  fi
  read -rp "Had baru (GB, 0 = tiada had, kosong = batal): " q
  [[ -z "${q:-}" ]] && { echo "Batal."; pause; return; }
  [[ "$q" =~ ^[0-9]+$ ]] || { echo -e "${R}Masukkan nombor bulat sahaja.${N}"; pause; return; }
  sed -i '/^quota_gb=/d' "$BW_STATE"
  echo "quota_gb=$q" >> "$BW_STATE"
  (( q > 0 )) && echo -e "${G}Had kuota diset: ${q} GB/bulan.${N}" || echo -e "${G}Had kuota dibuang (tiada had).${N}"
  pause
}

set_enforce() { # pilih tindakan automatik bila kuota dicapai
  need_config || return
  bw_save
  local last_in=0 last_out=0 total_in=0 total_out=0 month="" month_in=0 month_out=0 quota_gb=0 enforce_mode="none" quota_blocked=0
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  echo -e "${C}Mod sekarang: ${Y}${enforce_mode}${N}  |  ${C}Kuota: ${N}$([[ $quota_gb -gt 0 ]] && echo "${quota_gb} GB/bulan" || echo "BELUM SET (guna pilihan 11 dulu)")"
  echo " 1) Stop servis xray-socks bila cecah kuota"
  echo " 2) Blok port SOCKS (iptables DROP) bila cecah kuota"
  echo " 3) Paparan amaran sahaja (tiada tindakan)"
  echo " 0) Batal"
  local e; read -rp "Pilih [0-3]: " e
  case "$e" in
    1) enforce_mode="stop" ;;
    2) enforce_mode="block" ;;
    3) enforce_mode="none" ;;
    *) echo "Batal."; pause; return ;;
  esac
  bw_write_state
  echo -e "${G}Mod penguatkuasaan diset: ${enforce_mode}${N}"
  bw_enforce
  pause
}

reset_bw() { # reset statistik bandwidth
  echo -e "${C}--- Reset statistik bandwidth ---${N}"
  echo " 1) Reset 'Bulan ini' sahaja"
  echo " 2) Reset 'Keseluruhan' (termasuk Bulan ini)"
  echo " 0) Batal"
  local r; read -rp "Pilih [0-2]: " r
  [[ "$r" == "1" || "$r" == "2" ]] || { echo "Batal."; pause; return; }
  local a; read -rp "Pasti? [y/N]: " a
  [[ "${a,,}" == "y" ]] || { echo "Batal."; pause; return; }
  local last_in=0 last_out=0 total_in=0 total_out=0 month="" month_in=0 month_out=0 quota_gb=0 enforce_mode="none" quota_blocked=0
  [[ -f "$BW_STATE" ]] && source "$BW_STATE" 2>/dev/null
  if [[ "$r" == "1" ]]; then month_in=0; month_out=0
  else total_in=0; total_out=0; month_in=0; month_out=0; fi
  bw_write_state
  bw_enforce
  echo -e "${G}✅ Statistik direset. (Kuota & mod penguatkuasaan kekal.)${N}"
  pause
}

# ================= USER EXPIRED & RENEW =================
exp_get() { # $1=user -> tarikh ISO (atau kosong)
  [[ -f "$EXP_FILE" ]] && jq -r --arg u "$1" '.[$u] // empty' "$EXP_FILE" 2>/dev/null
}

exp_set() { # $1=user $2=YYYY-MM-DD (kosong = buang rekod)
  mkdir -p "$BW_DIR"
  [[ -f "$EXP_FILE" ]] || echo '{}' > "$EXP_FILE"
  if [[ -z "$2" ]]; then
    jq --arg u "$1" 'del(.[$u])' "$EXP_FILE" > "${EXP_FILE}.tmp" && mv "${EXP_FILE}.tmp" "$EXP_FILE"
  else
    jq --arg u "$1" --arg d "$2" '.[$u]=$d' "$EXP_FILE" > "${EXP_FILE}.tmp" && mv "${EXP_FILE}.tmp" "$EXP_FILE"
  fi
}

days_left() { # $1=YYYY-MM-DD -> baki hari (negatif = luput)
  local exp_ts now_ts
  exp_ts=$(date -d "$1 23:59:59" +%s 2>/dev/null) || { echo 0; return; }
  now_ts=$(date +%s)
  echo $(( (exp_ts - now_ts) / 86400 ))
}

check_expired() { # dipanggil cron — buang user yang dah luput
  [[ -f "$CONFIG_FILE" && -f "$EXP_FILE" ]] || return
  local today u exp changed=0
  today=$(date +%Y-%m-%d)
  while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    exp=$(exp_get "$u")
    [[ -z "$exp" ]] && continue
    if [[ "$exp" < "$today" ]]; then   # aktif sehingga 23:59 pada tarikh luput
      jq --arg u "$u" '.inbounds[0].settings.accounts |= map(select(.user != $u))' \
        "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      exp_set "$u" ""
      logger -t socks-bw "User '${u}' luput (${exp}) — dibuang automatik." 2>/dev/null || true
      changed=1
    fi
  done < <(jq -r '.inbounds[0].settings.accounts[].user' "$CONFIG_FILE" 2>/dev/null)
  (( changed == 1 )) && apply
}

set_expiry() { # set/tukar/buang tarikh luput user (kira dari hari ini)
  need_config || return
  list_users_raw
  local u days exp
  read -rp "Username untuk set expired: " u
  [[ -z "$u" ]] && return
  if ! jq -e --arg u "$u" '.inbounds[0].settings.accounts[]|select(.user==$u)' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${R}User '$u' tak dijumpai.${N}"; pause; return
  fi
  exp=$(exp_get "$u")
  if [[ -n "$exp" ]]; then
    echo -e "${C}Expired sekarang: ${Y}${exp}${N} (baki $(days_left "$exp") hari)"
  else
    echo -e "${C}Expired sekarang: ${N}TIADA"
  fi
  read -rp "Tempoh aktif baru (hari dari hari ini, 0 = buang had, kosong = batal): " days
  [[ -z "${days:-}" ]] && { echo "Batal."; pause; return; }
  [[ "$days" =~ ^[0-9]+$ ]] || { echo -e "${R}Masukkan nombor bulat sahaja.${N}"; pause; return; }
  if (( days == 0 )); then
    exp_set "$u" ""
    echo -e "${G}Had expired untuk '$u' dibuang.${N}"
  else
    exp=$(date -d "+${days} days" +%Y-%m-%d)
    exp_set "$u" "$exp"
    echo -e "${G}✅ User '$u' akan luput pada ${C}${exp}${G} (${days} hari).${N}"
  fi
  pause
}

renew_user() { # extend tempoh aktif (timbun dari tarikh luput semasa)
  need_config || return
  list_users_raw
  local u days exp base new_exp today
  read -rp "Username untuk renew: " u
  [[ -z "$u" ]] && return
  if ! jq -e --arg u "$u" '.inbounds[0].settings.accounts[]|select(.user==$u)' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${R}User '$u' tak dijumpai.${N}"; pause; return
  fi
  exp=$(exp_get "$u")
  if [[ -n "$exp" ]]; then
    echo -e "${C}Expired semasa: ${Y}${exp}${N} (baki $(days_left "$exp") hari)"
  else
    echo -e "${C}Expired semasa: ${N}TIADA (akan mula dari hari ini)"
  fi
  read -rp "Tambah berapa hari? (contoh: 30): " days
  [[ -z "${days:-}" ]] && { echo "Batal."; pause; return; }
  { [[ "$days" =~ ^[0-9]+$ ]] && (( days > 0 )); } || { echo -e "${R}Masukkan nombor bulat lebih dari 0.${N}"; pause; return; }
  today=$(date +%Y-%m-%d)
  if [[ -n "$exp" && ! "$exp" < "$today" ]]; then
    base="$exp"     # masih aktif → timbul dari tarikh luput semasa
  else
    base="$today"   # tiada had / dah luput → mula dari hari ini
  fi
  new_exp=$(date -d "$base +${days} days" +%Y-%m-%d)
  exp_set "$u" "$new_exp"
  echo -e "${G}✅ User '$u' direnew +${days} hari (dari ${base}).${N}"
  echo -e "${C}Expired baru: ${Y}${new_exp}${N} (baki $(days_left "$new_exp") hari)"
  pause
}

# ---------- Urus user ----------
add_user(){
  need_config || return
  local u p days exp=""
  read -rp "Username baru: " u
  [[ -z "$u" ]] && { echo -e "${R}Username kosong.${N}"; pause; return; }
  if jq -e --arg u "$u" '.inbounds[0].settings.accounts[]|select(.user==$u)' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${R}User '$u' sudah wujud.${N}"; pause; return
  fi
  read -rp "Password (kosong = auto-rawak): " p
  [[ -z "$p" ]] && { p="$(openssl rand -base64 18)"; echo -e "${Y}Password auto: ${C}$p${N}"; }
  read -rp "Tempoh aktif (hari, kosong/0 = tiada had): " days
  if [[ -n "${days:-}" && "$days" =~ ^[0-9]+$ ]] && (( days > 0 )); then
    exp=$(date -d "+${days} days" +%Y-%m-%d)
    echo -e "${Y}User akan luput pada: ${C}${exp}${N}"
  fi
  jq --arg u "$u" --arg p "$p" \
    '.inbounds[0].settings.accounts += [{"user":$u,"pass":$p}]' \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  [[ -n "$exp" ]] && exp_set "$u" "$exp"
  echo -e "${G}User '$u' ditambah.${N}"
  apply; pause
}

del_user(){
  need_config || return
  list_users_raw
  local u
  read -rp "Username untuk dibuang: " u
  [[ -z "$u" ]] && return
  if ! jq -e --arg u "$u" '.inbounds[0].settings.accounts[]|select(.user==$u)' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${R}User '$u' tak dijumpai.${N}"; pause; return
  fi
  jq --arg u "$u" \
    '.inbounds[0].settings.accounts |= map(select(.user != $u))' \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  exp_set "$u" ""   # buang rekod expired sekali
  echo -e "${G}User '$u' dibuang.${N}"
  apply; pause
}

change_pass(){
  need_config || return
  list_users_raw
  local u p
  read -rp "Username untuk tukar password: " u
  [[ -z "$u" ]] && return
  if ! jq -e --arg u "$u" '.inbounds[0].settings.accounts[]|select(.user==$u)' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${R}User '$u' tak dijumpai.${N}"; pause; return
  fi
  read -rp "Password baru (kosong = auto-rawak): " p
  [[ -z "$p" ]] && { p="$(openssl rand -base64 18)"; echo -e "${Y}Password auto: ${C}$p${N}"; }
  jq --arg u "$u" --arg p "$p" \
    '.inbounds[0].settings.accounts |= map(if .user==$u then .pass=$p else . end)' \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo -e "${G}Password '$u' dikemas kini.${N}"
  apply; pause
}

list_users_raw(){
  echo -e "${C}--- Senarai user (user : pass : expired) ---${N}"
  local u p exp dl
  while IFS=$'\t' read -r u p; do
    [[ -z "$u" ]] && continue
    exp=$(exp_get "$u")
    if [[ -n "$exp" ]]; then
      dl=$(days_left "$exp")
      if (( dl < 0 )); then
        printf "  %-15s : %-22s : ${R}%s (LUPUT)${N}\n" "$u" "$p" "$exp"
      else
        printf "  %-15s : %-22s : ${Y}%s${N} (%s hari lagi)\n" "$u" "$p" "$exp" "$dl"
      fi
    else
      printf "  %-15s : %-22s : -\n" "$u" "$p"
    fi
  done < <(jq -r '.inbounds[0].settings.accounts[] | "\(.user)\t\(.pass)"' "$CONFIG_FILE" 2>/dev/null)
  echo -e "${C}----------------------------------------------${N}"
}
list_users(){ need_config || return; list_users_raw; pause; }

show_info(){
  need_config || return
  local ip port
  ip=$(curl -s https://ifconfig.me || echo "IP-VPS")
  port=$(get_port)
  echo -e "${C}=== Maklumat Sambungan ===${N}"
  echo " Alamat : $ip"
  echo " Port   : $port"
  list_users_raw
  echo ""
  echo -e "${Y}Outbound untuk config client (contoh user pertama):${N}"
  local u p
  u=$(jq -r '.inbounds[0].settings.accounts[0].user // "USER"' "$CONFIG_FILE")
  p=$(jq -r '.inbounds[0].settings.accounts[0].pass // "PASS"' "$CONFIG_FILE")
  cat <<EOF
  {
    "protocol": "socks",
    "tag": "socks5",
    "settings": { "servers": [ {
      "address": "$ip", "port": $port,
      "users": [ { "user": "$u", "pass": "$p" } ]
    } ] }
  }
EOF
  pause
}

status(){ systemctl status xray-socks --no-pager -l | head -n 15; echo ""; ss -tlnp 2>/dev/null | grep ":$(get_port 2>/dev/null)" || true; pause; }

test_local(){
  need_config || return
  local u p port
  port=$(get_port)
  u=$(jq -r '.inbounds[0].settings.accounts[0].user // empty' "$CONFIG_FILE")
  p=$(jq -r '.inbounds[0].settings.accounts[0].pass // empty' "$CONFIG_FILE")
  [[ -z "$u" ]] && { echo -e "${R}Tiada user. Tambah user dulu.${N}"; pause; return; }
  echo "Menguji proxy (user: $u)..."
  local out
  out=$(curl -s --max-time 10 -x "socks5h://${u}:${p}@127.0.0.1:${port}" https://ifconfig.me || echo "GAGAL")
  echo -e "Hasil: ${C}${out}${N}"
  pause
}

uninstall(){
  read -rp "Pasti nak buang servis SOCKS5? (config & Xray kekal) [y/N]: " a
  [[ "${a,,}" == "y" ]] || { echo "Batal."; pause; return; }
  systemctl disable --now xray-socks 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  rm -f /etc/cron.d/socks-bw
  # buang sekatan kuota kalau ada
  local port; port=$(get_port 2>/dev/null)
  if [[ -n "${port:-}" && "$port" != "null" ]]; then
    iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null || true
  fi
  echo -e "${G}Servis xray-socks dibuang. (socks.json masih ada di $CONFIG_FILE)${N}"
  pause
}

menu(){
  clear

  # ===================== HEADER =====================
  local host_name cpu_model cpu_cores ram_used ram_total os_name kernel uptime ip port users
  host_name=$(hostname 2>/dev/null || echo "VPS")
  cpu_model=$(awk -F: '/model name|Hardware/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
  [[ -z "${cpu_model:-}" ]] && cpu_model=$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
  [[ -z "${cpu_model:-}" ]] && cpu_model="Unknown CPU"
  cpu_cores=$(nproc 2>/dev/null || echo "?")
  ram_total=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
  ram_used=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}')
  [[ -z "${ram_total:-}" ]] && ram_total="?"
  [[ -z "${ram_used:-}" ]] && ram_used="?"
  os_name=$(grep -oP '(?<=^PRETTY_NAME=").*(?="$)' /etc/os-release 2>/dev/null)
  [[ -z "${os_name:-}" ]] && os_name=$(awk -F= '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null)
  [[ -z "${os_name:-}" ]] && os_name="Unknown OS"
  kernel=$(uname -r 2>/dev/null || echo "?")
  uptime=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "?")
  ip=$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || echo "IP-VPS")
  port=$(get_port 2>/dev/null || echo "-")
  users="0"

  if [[ -f "$CONFIG_FILE" ]]; then
    users=$(jq '.inbounds[0].settings.accounts | length' "$CONFIG_FILE" 2>/dev/null || echo "?")
  fi

  # ===================== BANNER =====================
  echo -e "${C}"
  cat <<'EOF'
####   ####   #   #   ####
#   #  #   #  ##  #  #
####   #   #  # # #   ###
#  #   #   #  #  ##      #
#   #  ####   #   #  ####
EOF
  echo -e "${N}"
  echo ""
  echo -e "${G} VPS Script${N}"
  echo -e "${C}┌──────────────────────────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${Y}[ SERVER INFORMATION ]${N}                                   ${C}│${N}"
  echo -e "${C}├──────────────────────────────────────────────────────────────┤${N}"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "Hostname" "$host_name"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "CPU Model" "$cpu_model"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "CPU Cores" "$cpu_cores"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "RAM" "${ram_used} / ${ram_total} MB"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "OS" "$os_name"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "Kernel" "$kernel"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "Uptime" "$uptime"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "IP Address" "$ip"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "SOCKS Port" "$port"
  printf "${C}│${N} %-14s : %-42s ${C}│${N}\n" "Users" "$users"
  echo -e "${C}└──────────────────────────────────────────────────────────────┘${N}"
  echo ""

  # ===================== BANDWIDTH =====================
  if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${C} Traffic${N}                 ${G}Live${N}                    ${Y}Persistent${N}"
    echo -e " Download / Upload        $(get_bandwidth)"
    echo -e " $(get_bandwidth_persist)"
  else
    echo -e "${R} Status config : BELUM SETUP${N}"
  fi
  echo ""

  # ===================== MENU =====================
  echo -e "${C}╔══════════════════════════════════════════════════════════════╗${N}"
  echo -e "${C}║${N}                     ${Y}[ USER MENU ]${N}                       ${C}║${N}"
  echo -e "${C}╠══════════════════════════════════════════════════════════════╣${N}"
  echo -e "${C}║${N}  ${G}( 1 )${N} Tambah user             ${G}( 2 )${N} Buang user            ${C}║${N}"
  echo -e "${C}║${N}  ${G}( 3 )${N} Tukar password user     ${G}( 4 )${N} Senarai user           ${C}║${N}"
  echo -e "${C}║${N}  ${G}( 5 )${N} Maklumat sambungan      ${G}( 6 )${N} Status servis           ${C}║${N}"
  echo -e "${C}║${N}  ${G}( 7 )${N} Test proxy              ${G}( 8 )${N} Restart servis          ${C}║${N}"
  echo -e "${C}║${N}  ${G}(14 )${N} Set expired user       ${G}(15 )${N} Renew user              ${C}║${N}"
  echo -e "${C}╚══════════════════════════════════════════════════════════════╝${N}"
  echo ""
  echo -e "${C}╔══════════════════════════════════════════════════════════════╗${N}"
  echo -e "${C}║${N}                      ${Y}[ VPS MENU ]${N}                        ${C}║${N}"
  echo -e "${C}╠══════════════════════════════════════════════════════════════╣${N}"
  echo -e "${C}║${N}                          ${G}(10 )${N} Uninstall servis       ${C}║${N}"
  echo -e "${C}║${N}  ${G}(11 )${N} Set kuota bulanan      ${G}(12 )${N} Reset statistik        ${C}║${N}"
  echo -e "${C}║${N}  ${G}(13 )${N} Auto tindakan kuota    ${G}( 0 )${N} Keluar                 ${C}║${N}"
  echo -e "${C}╚══════════════════════════════════════════════════════════════╝${N}"
  echo ""
  echo -e "${C}┌──────────────────────────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${Y}Socks-Manager${N}                                             ${C}│${N}"
  echo -e "${C}│${N} ${G}Xray SOCKS5 • User • Expiry • Bandwidth • Quota${N}          ${C}│${N}"
  echo -e "${C}└──────────────────────────────────────────────────────────────┘${N}"
  echo ""
  read -rp " ${G}Select menu${N} : " ch

  case "$ch" in
    1) add_user ;;
    2) del_user ;;
    3) change_pass ;;
    4) list_users ;;
    5) show_info ;;
    6) status ;;
    7) test_local ;;
    8) restart_service; pause ;;
    10) uninstall ;;
    11) set_quota ;;
    12) reset_bw ;;
    13) set_enforce ;;
    14) set_expiry ;;
    15) renew_user ;;
    0) exit 0 ;;
    *) echo -e "${R}Pilihan tak sah.${N}"; sleep 1 ;;
  esac
}

# ---------- Mod cron (tanpa menu) ----------
if [[ "${1:-}" == "--bw-save" ]]; then
  bw_save
  check_expired
  bw_enforce
  exit 0
fi

# ---------- Main loop ----------
while true; do menu; done
