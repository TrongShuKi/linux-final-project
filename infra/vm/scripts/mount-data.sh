#!/usr/bin/env bash
# mount-data.sh - Định dạng (nếu chưa có filesystem) và mount ổ data qua /etc/fstab bằng UUID.
# KHÔNG format nếu ổ đã có filesystem. Chạy bằng sudo.
set -Eeuo pipefail

LOG_TAG="mount-data"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") -m <thư mục mount> [-d <thiết bị>] [-h]
  -m   thư mục mount, vd: /srv/data (lab-web) hoặc /srv/backup (lab-bkp)
  -d   thiết bị (mặc định: /dev/disk/by-id/google-data)
  -h   hiện trợ giúp
Thêm dòng UUID=... <mount> ext4 defaults,nofail 0 2 vào /etc/fstab, rồi mount -a.
USAGE
}

mountpoint_dir=""
device="/dev/disk/by-id/google-data"
while getopts ':m:d:h' opt; do
  case "$opt" in
    m) mountpoint_dir="$OPTARG" ;;
    d) device="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root
[[ -n "$mountpoint_dir" ]] || { usage >&2; die "thiếu -m <thư mục mount>"; }
[[ -e "$device" ]] || die "không thấy thiết bị $device (xem lsblk và ls -l /dev/disk/by-id/)"

if blkid "$device" >/dev/null 2>&1; then
  log "$device đã có filesystem, KHÔNG format"
else
  log "$device chưa có filesystem, tạo ext4"
  mkfs.ext4 -L labdata "$device"
fi

uuid="$(blkid -s UUID -o value "$device")"
[[ -n "$uuid" ]] || die "không đọc được UUID của $device"

mkdir -p "$mountpoint_dir"
if grep -q "UUID=${uuid}" /etc/fstab; then
  log "fstab đã có UUID $uuid"
else
  printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' "$uuid" "$mountpoint_dir" >> /etc/fstab
  log "đã thêm vào /etc/fstab"
fi

mount -a
findmnt "$mountpoint_dir" >&2
df -h "$mountpoint_dir" >&2
log "xong. Nhớ reboot một lần để xác nhận mount còn sau khởi động"
