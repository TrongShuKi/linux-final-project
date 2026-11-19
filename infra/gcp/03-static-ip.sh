#!/usr/bin/env bash
# 03-static-ip.sh - "Nâng" IP public đang dùng của 2 VM thành IP tĩnh (địa chỉ không đổi).
# shellcheck disable=SC2154
set -Eeuo pipefail

LOG_TAG="gcp-static-ip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/gcp.sh
source "$SCRIPT_DIR/../lib/gcp.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: $(basename "$0") [-n] [-h]
  -n   chạy thử (dry-run)
  -h   hiện trợ giúp
Với mỗi VM: lấy IP public hiện tại rồi reserve thành địa chỉ tĩnh <tên VM>-ip.
Nhớ xóa IP tĩnh sau khi nộp bài (99-teardown.sh) để khỏi bị tính phí.
USAGE
}

while getopts ':nh' opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

load_gcp_env "$SCRIPT_DIR"

promote_ip() {
  local vm="$1" addr="${1}-ip" ip
  if gcloud_exists compute addresses describe "$addr" --region="$REGION"; then
    log "địa chỉ $addr đã có, bỏ qua"
    return 0
  fi
  ip="$(gcloud compute instances describe "$vm" --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
  [[ -n "$ip" ]] || die "VM $vm chưa có IP public"
  run gcloud compute addresses create "$addr" --addresses="$ip" --region="$REGION"
  log "IP tĩnh của $vm: $ip (ghi vào mục 4 của TV1_MASTER.md)"
}

promote_ip "$WEB_VM"
promote_ip "$BKP_VM"
