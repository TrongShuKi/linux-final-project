#!/usr/bin/env bash
# add_user.sh - Tạo user cho thành viên, nạp public key, cho vào nhóm labadmin (sudo).
# Chạy bằng sudo trên CẢ HAI VM. Chạy lại an toàn (không nạp trùng key).
set -Eeuo pipefail

LOG_TAG="add-user"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
setup_traps

usage() {
  cat <<USAGE
Dùng: sudo $(basename "$0") -u <username> (-k "<public key>" | -f <file .pub>) [-h]
  -u   username (chữ thường, không dấu, không khoảng trắng)
  -k   nội dung public key (ssh-ed25519 AAAA...)
  -f   đường dẫn file public key
  -h   hiện trợ giúp
Tạo user (không mật khẩu), nạp key vào ~/.ssh/authorized_keys, thêm vào nhóm labadmin.
Lần đầu chạy sẽ cài /etc/sudoers.d/90-labadmin (sudo không cần mật khẩu cho labadmin).
Nếu AllowUsers đang bật mà user chưa nằm trong danh sách, script sẽ cảnh báo.
USAGE
}

user=""
key=""
while getopts ':u:k:f:h' opt; do
  case "$opt" in
    u) user="$OPTARG" ;;
    k) key="$OPTARG" ;;
    f) [[ -r "$OPTARG" ]] || die "không đọc được file $OPTARG"
       key="$(head -n 1 "$OPTARG")" ;;
    h) usage; exit 0 ;;
    *) usage >&2; die "tùy chọn không hợp lệ" ;;
  esac
done

require_root
[[ -n "$user" && -n "$key" ]] || { usage >&2; die "thiếu -u hoặc public key (-k/-f)"; }

user_re='^[a-z][a-z0-9_-]{1,30}$'
key_re='^ssh-ed25519 AAAA[A-Za-z0-9+/=]+'
[[ "$user" =~ $user_re ]] || die "username không hợp lệ: $user"
[[ "$key" =~ $key_re ]] || die "key phải là public key ssh-ed25519 (bắt đầu bằng ssh-ed25519 AAAA...)"

groupadd -f labadmin

sudoers_target="/etc/sudoers.d/90-labadmin"
if [[ ! -f "$sudoers_target" ]]; then
  install -m 440 "$SCRIPT_DIR/../etc/sudoers.d/90-labadmin" "$sudoers_target"
  if ! visudo -cf "$sudoers_target" >/dev/null; then
    rm -f "$sudoers_target"
    die "file sudoers không hợp lệ, đã gỡ"
  fi
  log "đã cài $sudoers_target"
fi

if id "$user" >/dev/null 2>&1; then
  log "user $user đã tồn tại"
else
  adduser --disabled-password --gecos "" "$user"
fi
usermod -aG labadmin "$user"

home_dir="/home/$user"
install -d -m 700 -o "$user" -g "$user" "$home_dir/.ssh"
authorized="$home_dir/.ssh/authorized_keys"
touch "$authorized"
if grep -qxF "$key" "$authorized"; then
  log "key đã có trong $authorized"
else
  printf '%s\n' "$key" >> "$authorized"
  log "đã nạp key"
fi
chown "$user:$user" "$authorized"
chmod 600 "$authorized"

allowed="$(sshd -T 2>/dev/null | awk 'tolower($1)=="allowusers"{print $2}')" || allowed=""
if [[ -n "$allowed" ]] && ! grep -qxF "$user" <<<"$allowed"; then
  log "CẢNH BÁO: AllowUsers đang bật và chưa có $user, nên $user CHƯA SSH được."
  log "Thêm user vào AllowUsers trong /etc/ssh/sshd_config.d/99-hardening.conf rồi: sshd -t && systemctl reload ssh"
fi

log "xong: $user"
