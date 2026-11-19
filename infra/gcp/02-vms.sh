#!/usr/bin/env bash
# 02-vms.sh - Tạo 2 VM Ubuntu 22.04 (web + backup), mỗi VM kèm 1 ổ data.
# Chạy lại an toàn: VM đã có thì bỏ qua.
# shellcheck disable=SC2154
set -Eeuo pipefail

LOG_TAG="gcp-vms"
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
Tạo 2 VM theo env.sh: WEB_VM (tag web) và BKP_VM, mỗi VM có boot disk + ổ data (device-name=data).
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

# create_vm <tên> <ip nội bộ> [tags]
create_vm() {
  local name="$1" ip="$2" tags="${3:-}"
  if gcloud_exists compute instances describe "$name" --zone="$ZONE"; then
    log "VM $name đã có, bỏ qua"
    return 0
  fi
  local args=(compute instances create "$name"
    --zone="$ZONE" --machine-type="$MACHINE_TYPE"
    --subnet="$SUBNET" --private-network-ip="$ip"
    --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud
    --boot-disk-size="$BOOT_SIZE" --boot-disk-type=pd-standard
    --metadata=enable-oslogin=FALSE
    --create-disk="name=${name}-data,size=${DATA_SIZE},type=pd-standard,device-name=data,auto-delete=yes")
  [[ -z "$tags" ]] || args+=(--tags="$tags")
  run gcloud "${args[@]}"
}

create_vm "$WEB_VM" "$WEB_IP_INT" "web"
create_vm "$BKP_VM" "$BKP_IP_INT"

log "xong. Nếu báo hết tài nguyên ở zone $ZONE, đổi ZONE trong env.sh sang -a hoặc -c"
