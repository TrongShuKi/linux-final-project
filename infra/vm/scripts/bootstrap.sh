#!/usr/bin/env bash
# bootstrap.sh - Thiết lập cơ bản cho mỗi VM: timezone, /etc/hosts, swap, lưu lịch sử lệnh.
# Chạy lại an toàn (idempotent). Chạy bằng sudo trên CẢ HAI VM.
set -Eeuo pipefail

LOG_TAG="bootstrap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

WEB_IP_INT="${WEB_IP_INT:-10.10.0.10}"
BKP_IP_INT="${BKP_IP_INT:-10.10.0.20}"

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") [-u] [-s] [-h]
  -u   chạy apt update && apt upgrade
  -s   bỏ qua tạo swap 1 GB
  -h   hiện trợ giúp
Việc làm: đặt timezone Asia/Ho_Chi_Minh, thêm lab-web/lab-bkp vào /etc/hosts,
tạo swap 1 GB, cài /etc/profile.d/lab-history.sh.
Có thể đổi IP nội bộ qua biến môi trường WEB_IP_INT và BKP_IP_INT.
USAGE
}

do_upgrade=0
do_swap=1
while getopts ':ush' opt; do
  case "$opt" in
    u) do_upgrade=1 ;;
    s) do_swap=0 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root

log "hostname hiện tại: $(hostname)"
timedatectl set-timezone Asia/Ho_Chi_Minh

if [[ "$do_upgrade" -eq 1 ]]; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
fi

add_hosts_entry() {
  local ip="$1" name="$2"
  if grep -qE "^[0-9.]+[[:space:]]+${name}([[:space:]]|\$)" /etc/hosts; then
    log "/etc/hosts đã có $name"
    return 0
  fi
  printf '%s %s\n' "$ip" "$name" >> /etc/hosts
  log "đã thêm $name vào /etc/hosts"
}
add_hosts_entry "$WEB_IP_INT" lab-web
add_hosts_entry "$BKP_IP_INT" lab-bkp

if [[ "$do_swap" -eq 1 ]]; then
  if swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
    log "swap /swapfile đã bật"
  else
    [[ -e /swapfile ]] || fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -qE '^/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "đã bật swap 1 GB"
  fi
fi

install -m 644 "$SCRIPT_DIR/../etc/profile.d/lab-history.sh" /etc/profile.d/lab-history.sh
log "đã cài /etc/profile.d/lab-history.sh (có hiệu lực ở phiên đăng nhập mới)"

free -h >&2
log "xong"
