#!/usr/bin/env bash
# install-auditd.sh - Cài auditd và luật theo dõi /etc/passwd, /etc/shadow. Chạy bằng sudo.
set -Eeuo pipefail

LOG_TAG="install-auditd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") [-x] [-h]
  -x   cài thêm luật ghi mọi lệnh chạy bằng root theo từng người (root_cmds), log tăng nhanh
  -h   hiện trợ giúp
USAGE
}

with_rootcmds=0
while getopts ':xh' opt; do
  case "$opt" in
    x) with_rootcmds=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root

DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins
install -m 640 "$SCRIPT_DIR/../etc/audit/rules.d/lab.rules" /etc/audit/rules.d/lab.rules
if [[ "$with_rootcmds" -eq 1 ]]; then
  install -m 640 "$SCRIPT_DIR/../etc/audit/optional/lab-rootcmds.rules" /etc/audit/rules.d/lab-rootcmds.rules
fi

augenrules --load
systemctl enable --now auditd

auditctl -l | grep -q 'shadow_access' || die "luật shadow_access chưa được nạp"
log "đã nạp luật. Test: sudo cat /etc/shadow >/dev/null; sudo ausearch -k shadow_access -i | tail"
