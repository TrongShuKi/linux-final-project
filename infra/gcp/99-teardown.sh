#!/usr/bin/env bash
# 99-teardown.sh - XÓA toàn bộ tài nguyên của đồ án trên GCP (VM, disk, IP tĩnh, snapshot, firewall, VPC).
# Dùng sau khi nộp bài và chấm xong để khỏi bị tính phí. KHÔNG THỂ HOÀN TÁC.
# shellcheck disable=SC2154
set -Eeuo pipefail

LOG_TAG="gcp-teardown"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/gcp.sh
source "$SCRIPT_DIR/../lib/gcp.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: $(basename "$0") [-n] [-y] [-h]
  -n   chạy thử (dry-run): chỉ in lệnh xóa
  -y   không hỏi xác nhận
  -h   hiện trợ giúp
Xóa VM, disk, IP tĩnh, snapshot tên lab-*, firewall lab-*, subnet và VPC.
USAGE
}

assume_yes=0
while getopts ':nyh' opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    y) assume_yes=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

load_gcp_env "$SCRIPT_DIR"

if [[ "$assume_yes" -ne 1 && "$DRY_RUN" != "1" ]]; then
  log "Sắp XÓA tài nguyên trong project $PROJECT"
  read -r -p "Gõ XOA để xác nhận: " answer
  [[ "$answer" == "XOA" ]] || die "đã hủy"
fi

for vm in "$WEB_VM" "$BKP_VM"; do
  if gcloud_exists compute instances describe "$vm" --zone="$ZONE"; then
    run gcloud compute instances delete "$vm" --zone="$ZONE" --quiet
  fi
done

for addr in "${WEB_VM}-ip" "${BKP_VM}-ip"; do
  if gcloud_exists compute addresses describe "$addr" --region="$REGION"; then
    run gcloud compute addresses delete "$addr" --region="$REGION" --quiet
  fi
done

mapfile -t snaps < <(gcloud compute snapshots list --filter="name~^lab-" --format='value(name)')
if ((${#snaps[@]} > 0)); then
  run gcloud compute snapshots delete "${snaps[@]}" --quiet
fi

for rule in lab-allow-internal lab-allow-ssh lab-allow-web; do
  if gcloud_exists compute firewall-rules describe "$rule"; then
    run gcloud compute firewall-rules delete "$rule" --quiet
  fi
done

if gcloud_exists compute networks subnets describe "$SUBNET" --region="$REGION"; then
  run gcloud compute networks subnets delete "$SUBNET" --region="$REGION" --quiet
fi
if gcloud_exists compute networks describe "$NETWORK"; then
  run gcloud compute networks delete "$NETWORK" --quiet
fi

log "xong. Kiểm tra lại trên Console (Billing) rằng không còn tài nguyên tính phí"
