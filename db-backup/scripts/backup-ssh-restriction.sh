#!/usr/bin/env bash
#
# backup-ssh-restriction.sh — Forced-command wrapper cho user backup trên lab-bkp.
# Chỉ cho phép các lệnh rsync đồng bộ và danh sách phục vụ sao lưu vào /srv/backup.
# Mọi lệnh shell tương tác hoặc can thiệp ngoài thư mục đều bị từ chối.
#
# Cài đặt: thêm vào ~/.ssh/authorized_keys của user backup trên lab-bkp:
#   command="/usr/local/bin/backup-ssh-restriction.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty <public-key>
#
set -euo pipefail

ORIG_CMD="${SSH_ORIGINAL_COMMAND:-}"

if [[ -z "${ORIG_CMD}" ]]; then
    echo "LỖI: Truy cập shell tương tác không được phép." >&2
    exit 1
fi

ALLOWED_DIR="${ALLOWED_DIR:-/srv/backup}"

# Từ chối path traversal
if [[ "${ORIG_CMD}" == *".."* ]]; then
    echo "LỖI: Phát hiện ký tự không an toàn (path traversal)." >&2
    exit 1
fi

# Chuyển lệnh thành mảng để exec trực tiếp (không dùng eval)
IFS=' ' read -r -a CMD_ARRAY <<< "${ORIG_CMD}"

case "${ORIG_CMD}" in
    list-backups)
        # Liệt kê danh sách archive theo thời gian mới nhất xếp trước
        # shellcheck disable=SC2086
        ls -t "${ALLOWED_DIR}"/backup_*.tar.gz 2>/dev/null || true
        exit 0
        ;;
    prune-backups:*)
        # Trích xuất số ngày N từ lệnh "prune-backups:<N>"
        days="${ORIG_CMD#prune-backups:}"
        # Validate chặt chẽ: N bắt buộc chỉ gồm các chữ số nguyên dương [0-9]+
        if [[ ! "${days}" =~ ^[0-9]+$ ]]; then
            echo "LỖI: Tham số số ngày không hợp lệ (chỉ chấp nhận số nguyên dương): ${days}" >&2
            exit 1
        fi
        # Thực thi dọn dẹp cục bộ an toàn, tuyệt đối không nhận script qua stdin
        find "${ALLOWED_DIR}" -maxdepth 1 -name 'backup_*.tar.gz' -mtime "+${days}" -delete
        exit 0
        ;;
    rsync\ --server*"${ALLOWED_DIR}"*)
        exec "${CMD_ARRAY[@]}"
        ;;
    *)
        echo "LỖI: Lệnh không nằm trong danh mục cho phép (forced-command whitelist)." >&2
        echo "Lệnh bị từ chối: ${ORIG_CMD}" >&2
        exit 1
        ;;
esac
