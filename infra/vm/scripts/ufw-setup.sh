#!/usr/bin/env bash
# ufw-setup.sh - Bật UFW: mặc định chặn chiều vào, chỉ mở cổng cần thiết.
# Mở cổng SSH TRƯỚC khi bật UFW để không tự khóa. Chạy bằng sudo.
set -Eeuo pipefail

LOG_TAG="ufw-setup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") [-p "<cổng SSH cách nhau bằng dấu cách>"] [-w] [-h]
  -p   các cổng SSH (mặc định: "22 2222")
  -w   mở thêm 80 và 443 (chỉ dùng trên lab-web)
  -h   hiện trợ giúp
Mặc định: deny incoming, allow outgoing. Chỉ mở các cổng được chỉ định.
USAGE
}

ssh_ports="22 2222"
open_web=0
while getopts ':p:wh' opt; do
  case "$opt" in
    p) ssh_ports="$OPTARG" ;;
    w) open_web=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root
require_cmd ufw

read -r -a ports <<<"$ssh_ports"
((${#ports[@]} > 0)) || die "danh sách cổng SSH rỗng"
for p in "${ports[@]}"; do
  [[ "$p" =~ ^[0-9]+$ ]] || die "cổng không hợp lệ: $p"
done

ufw default deny incoming
ufw default allow outgoing
for p in "${ports[@]}"; do
  ufw allow "${p}/tcp" comment "SSH-${p}"
done
if [[ "$open_web" -eq 1 ]]; then
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
fi

ufw --force enable
ufw status verbose >&2
log "xong. Chụp ảnh 'ufw status verbose' làm bằng chứng cho báo cáo"
