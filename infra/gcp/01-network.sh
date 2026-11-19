#!/usr/bin/env bash
# 01-network.sh - Tạo VPC, subnet và 3 firewall rule VPC cho đồ án.
# Chạy trong Cloud Shell hoặc máy có gcloud. Chạy lại nhiều lần an toàn (bỏ qua cái đã có).
# Các biến (NETWORK, ZONE...) lấy từ env.sh nên tắt cảnh báo SC2154.
# shellcheck disable=SC2154
set -Eeuo pipefail

LOG_TAG="gcp-network"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/gcp.sh
source "$SCRIPT_DIR/../lib/gcp.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: $(basename "$0") [-n] [-h]
  -n   chạy thử (dry-run): chỉ in lệnh, không tạo gì
  -h   hiện trợ giúp
Tạo: VPC custom, subnet, firewall lab-allow-internal / lab-allow-ssh (22,2222) / lab-allow-web (80,443).
Cần file env.sh (xem env.sh.example).
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

if gcloud_exists compute networks describe "$NETWORK"; then
  log "VPC $NETWORK đã có, bỏ qua"
else
  run gcloud compute networks create "$NETWORK" --subnet-mode=custom
fi

if gcloud_exists compute networks subnets describe "$SUBNET" --region="$REGION"; then
  log "subnet $SUBNET đã có, bỏ qua"
else
  run gcloud compute networks subnets create "$SUBNET" \
    --network="$NETWORK" --range="$SUBNET_RANGE" --region="$REGION"
fi

# ensure_fw <tên> <allow> <source-ranges> [target-tags]
ensure_fw() {
  local name="$1" allow="$2" ranges="$3" tags="${4:-}"
  if gcloud_exists compute firewall-rules describe "$name"; then
    log "firewall $name đã có, bỏ qua"
    return 0
  fi
  local args=(compute firewall-rules create "$name" --network="$NETWORK" --allow="$allow" --source-ranges="$ranges")
  [[ -z "$tags" ]] || args+=(--target-tags="$tags")
  run gcloud "${args[@]}"
}

ensure_fw lab-allow-internal "tcp,udp,icmp" "$SUBNET_RANGE"
ensure_fw lab-allow-ssh "tcp:22,tcp:2222" "0.0.0.0/0"
ensure_fw lab-allow-web "tcp:80,tcp:443" "0.0.0.0/0" "web"

log "xong phần mạng"
