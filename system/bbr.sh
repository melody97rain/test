#!/usr/bin/env bash
set -Eeuo pipefail

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Harus dijalankan sebagai root." >&2; exit 1; }; }
log() { printf '%b
' "$*"; }
ensure_line_in_file() { local f="$1" l="$2"; install -m 0755 -d "$(dirname "$f")" 2>/dev/null || true; touch "$f"; grep -Fxq -- "$l" "$f" || printf '%s
' "$l" >> "$f"; }

choose_cc() {
  local avail
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  # Prefer bbrplus if kernel supports it, else bbr2, else bbr
  if grep -qw bbrplus <<<"$avail"; then echo bbrplus
  elif grep -qw bbr2 <<<"$avail"; then echo bbr2
  else echo bbr
  fi
}

install_bbr_plus_safe() {
  log "\u001B[32;1m== BBR+ (aman, tanpa kernel custom) ==\u001B[0m"

  # Pastikan modul BBR ada (aman jika built-in)
  modprobe -q tcp_bbr 2>/dev/null || true

  # Autoload tcp_bbr saat boot (tidak menambahkan tcp_bbr2 agar tidak error di kernel tanpa modul itu)
  ensure_line_in_file "/etc/modules-load.d/bbr.conf" "tcp_bbr"

  # Pilih CC terbaik yang tersedia: bbrplus > bbr2 > bbr
  local cc; cc="$(choose_cc)"

  # BBR dan fq qdisc
  cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = ${cc}
EOF

  # Tuning “plus” yang aman di kernel modern
  cat > /etc/sysctl.d/99-net-optimizations.conf <<'EOF'
# File descriptor dan antrean
fs.file-max = 51200
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096

# TCP baseline
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192

# Memori TCP
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864

# MTU probing dan Fast Open
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3

# HTTP/2 send buffer control (disarankan 16KB)
net.ipv4.tcp_notsent_lowat = 16384

# Hindari slow-start setelah idle untuk koneksi panjang/latensi tinggi
net.ipv4.tcp_slow_start_after_idle = 0
EOF

  # Terapkan dan verifikasi
  sysctl --system >/dev/null

  if sysctl -n net.ipv4.tcp_congestion_control | grep -Eq 'bbr|bbr2|bbrplus' \
     && sysctl -n net.core.default_qdisc | grep -qx fq; then
    log "\u001B[32mBBR+ (aman) aktif dengan CC: $(sysctl -n net.ipv4.tcp_congestion_control).\u001B[0m"
  else
    log "\u001B[31mGagal mengaktifkan BBR+.\u001B[0m"; exit 1
  fi

  # Limits (ulimit) untuk proses
  ensure_line_in_file "/etc/security/limits.conf" "* soft nofile 51200"
  ensure_line_in_file "/etc/security/limits.conf" "* hard nofile 51200"
  ensure_line_in_file "/etc/security/limits.conf" "root soft nofile 51200"
  ensure_line_in_file "/etc/security/limits.conf" "root hard nofile 51200"
}

main() {
  require_root
  install_bbr_plus_safe
  # opsional: hapus skrip jika disimpan di /root
  rm -f /root/bbr.sh 2>/dev/null || true
}

main "$@"
