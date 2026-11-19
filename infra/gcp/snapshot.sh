#!/usr/bin/env bash
# snapshot.sh - Chụp snapshot disk (boot + data) của cả 2 VM với một nhãn, vd: clean, truoc-ssh, truoc-demo.
# shellcheck disable=SC2154
set -Eeuo pipefail

LOG_TAG="gcp-snapshot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/gcp.sh
source "$SCRIPT_DIR/../lib/gcp.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: $(basename "$0") -l <nhãn> [-n] [-h]
  -l   nhãn snapshot (chữ thường, số, dấu gạch ngang), vd: clean
  -n   chạy thử (dry-run)
  -h   hiện trợ giúp
Tạo snapshot tên <disk>-<nhãn> cho 4 disk: boot + data của mỗi VM.
USAGE
}

label=""
while getopts ':l:nh' opt; do
  case "$opt" in
    l) label="$OPTARG" ;;
    n) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

[[ -n "$label" ]] || { usage >&2; die "thiếu -l <nhãn>"; }
[[ "$label" =~ ^[a-z0-9-]+$ ]] || die "nhãn chỉ gồm chữ thường, số, dấu gạch ngang"

load_gcp_env "$SCRIPT_DIR"

for disk in "$WEB_VM" "${WEB_VM}-data" "$BKP_VM" "${BKP_VM}-data"; do
  run gcloud compute disks snapshot "$disk" --zone="$ZONE" --snapshot-names="${disk}-${label}"
done

log "xong. Danh sách: gcloud compute snapshots list"
