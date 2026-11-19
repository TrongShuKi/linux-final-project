#!/usr/bin/env bash
# harden-ssh.sh - Cài cấu hình SSH hardening (tắt root, chỉ dùng khóa, AllowUsers, 2 cổng).
# Có chống tự khóa: kiểm tra người chạy nằm trong AllowUsers, cổng đã mở ở UFW, sshd -t, tự hoàn tác nếu lỗi.
# GIỮ MỘT PHIÊN SSH CŨ MỞ và test bằng phiên mới trước khi đóng. Chạy bằng sudo.
set -Eeuo pipefail

LOG_TAG="harden-ssh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") -u "<user1 user2 ...>" [-t <file mẫu>] [-h]
  -u   danh sách user được phép SSH (AllowUsers), cách nhau bằng dấu cách
  -t   file mẫu (mặc định: ../etc/ssh/sshd_config.d/99-hardening.conf)
  -h   hiện trợ giúp
Người chạy lệnh (SUDO_USER) phải nằm trong danh sách để tránh tự khóa.
USAGE
}

users=""
template="$SCRIPT_DIR/../etc/ssh/sshd_config.d/99-hardening.conf"
while getopts ':u:t:h' opt; do
  case "$opt" in
    u) users="$OPTARG" ;;
    t) template="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root
[[ -n "$users" ]] || { usage >&2; die "thiếu -u <danh sách user>"; }
[[ -r "$template" ]] || die "không đọc được file mẫu $template"

user_re='^[a-z][a-z0-9_-]{1,30}$'
read -r -a user_list <<<"$users"
for u in "${user_list[@]}"; do
  [[ "$u" =~ $user_re ]] || die "username không hợp lệ: $u"
  id "$u" >/dev/null 2>&1 || die "user $u chưa tồn tại (chạy add_user.sh trước)"
done

caller="${SUDO_USER:-}"
if [[ -n "$caller" && "$caller" != "root" ]]; then
  [[ " ${user_list[*]} " == *" $caller "* ]] || die "người chạy ($caller) không nằm trong danh sách AllowUsers, sẽ tự khóa mình"
fi

# Các cổng trong file mẫu phải đã mở ở UFW (nếu UFW đang bật).
if ufw status 2>/dev/null | grep -q '^Status: active'; then
  while read -r port; do
    ufw status | grep -qE "^${port}/tcp[[:space:]]+ALLOW" || die "cổng ${port}/tcp chưa mở ở UFW (chạy ufw-setup.sh trước)"
  done < <(awk '/^Port /{print $2}' "$template")
fi

target="/etc/ssh/sshd_config.d/99-hardening.conf"
backup=""
if [[ -f "$target" ]]; then
  backup="$(mktemp /root/99-hardening.conf.bak.XXXXXX)"
  cp -p "$target" "$backup"
  log "đã sao lưu cấu hình cũ: $backup"
fi

sed "s/__ALLOW_USERS__/${users}/" "$template" > "$target"
chmod 644 "$target"

if ! sshd -t; then
  log "sshd -t báo lỗi, hoàn tác"
  if [[ -n "$backup" ]]; then cp -p "$backup" "$target"; else rm -f "$target"; fi
  die "cấu hình không hợp lệ, đã hoàn tác"
fi

systemctl reload ssh
log "đã reload sshd. Kiểm tra giá trị hiệu lực:"
sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|maxauthtries) ' >&2 || true
log "BƯỚC TIẾP: mở PHIÊN MỚI để test đăng nhập trước khi đóng phiên cũ"
