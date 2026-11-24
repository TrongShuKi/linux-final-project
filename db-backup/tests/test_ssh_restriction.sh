#!/usr/bin/env bash
#
# test_ssh_restriction.sh — Public Tests cho forced-command wrapper backup-ssh-restriction.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WRAPPER_SCRIPT="${PROJECT_ROOT}/db-backup/scripts/backup-ssh-restriction.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

make_sandbox() {
    local sandbox
    sandbox="$(mktemp -d)"
    mkdir -p "${sandbox}/srv/backup"
    mkdir -p "${sandbox}/bin"
    echo "${sandbox}"
}

write_stub() {
    local bindir="$1"
    local name="$2"
    local body="$3"
    printf '#!/usr/bin/env bash\n%s\n' "${body}" > "${bindir}/${name}"
    chmod +x "${bindir}/${name}"
}

# ========================================================
# T01: Interactive shell không có SSH_ORIGINAL_COMMAND -> Exit 1
# ========================================================
t01_interactive_shell_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "không được phép"; then
        pass "T01: Truy cập shell tương tác (rỗng) bị từ chối với exit 1"
    else
        fail "T01: Mong đợi exit khác 0 và báo lỗi shell tương tác (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T02: Path Traversal (chứa ..) -> Exit 1
# ========================================================
t02_path_traversal_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="ls /srv/backup/../etc" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "path traversal"; then
        pass "T02: Path traversal bị từ chối với exit 1"
    else
        fail "T02: Mong đợi exit khác 0 khi phát hiện .. (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T03: Lệnh tùy ý không nằm trong whitelist -> Exit 1
# ========================================================
t03_unwhitelisted_commands_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="whoami" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "LỖI: Lệnh không nằm trong danh mục cho phép"; then
        pass "T03: Lệnh ngoài whitelist ('whoami') bị từ chối với exit 1"
    else
        fail "T03: Mong đợi exit khác 0 với 'whoami' (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T04: Lệnh nguy hiểm (cat, rm) -> Exit 1
# ========================================================
t04_dangerous_command_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="cat /etc/shadow" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "LỖI: Lệnh không nằm trong danh mục cho phép"; then
        pass "T04: Lệnh nguy hiểm ('cat /etc/shadow') bị từ chối với exit 1"
    else
        fail "T04: Mong đợi exit khác 0 với 'cat /etc/shadow' (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T05: Lệnh list-backups trả về danh sách backup hợp lệ -> Exit 0
# ========================================================
t05_list_backups_success() {
    local sandbox
    sandbox="$(make_sandbox)"
    # Tạo fake backup files
    touch "${sandbox}/srv/backup/backup_20261124_100000.tar.gz"
    sleep 1
    touch "${sandbox}/srv/backup/backup_20261124_110000.tar.gz"

    local rc=0
    local out
    out="$(ALLOWED_DIR="${sandbox}/srv/backup" SSH_ORIGINAL_COMMAND="list-backups" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    rm -rf "${sandbox}"

    if [[ $rc -eq 0 ]] && echo "${out}" | grep -q "backup_20261124_110000.tar.gz"; then
        pass "T05: Lệnh 'list-backups' liệt kê thành công các file backup (mới nhất xếp trước)"
    else
        fail "T05: Lệnh 'list-backups' thất bại (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T06: Lệnh list-backups khi thư mục rỗng -> Exit 0
# ========================================================
t06_list_backups_empty_dir() {
    local sandbox
    sandbox="$(make_sandbox)"

    local rc=0
    local out
    out="$(ALLOWED_DIR="${sandbox}/srv/backup" SSH_ORIGINAL_COMMAND="list-backups" bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    rm -rf "${sandbox}"

    if [[ $rc -eq 0 ]]; then
        pass "T06: Lệnh 'list-backups' khi không có file backup trả về exit 0 sạch"
    else
        fail "T06: Lệnh 'list-backups' khi không có file trả về lỗi (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T07: Lệnh rsync --server hợp lệ -> Chấp nhận thực thi
# ========================================================
t07_rsync_command_allowed() {
    local sandbox
    sandbox="$(make_sandbox)"
    write_stub "${sandbox}/bin" rsync 'echo "MOCK_RSYNC_CALLED"; exit 0'

    local rc=0
    local out
    out="$(PATH="${sandbox}/bin:${PATH}" ALLOWED_DIR="${sandbox}/srv/backup" \
        SSH_ORIGINAL_COMMAND="rsync --server -vlogDtpre.iLsfxCIvu . ${sandbox}/srv/backup/" \
        bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    rm -rf "${sandbox}"

    if [[ $rc -eq 0 ]] && echo "${out}" | grep -q "MOCK_RSYNC_CALLED"; then
        pass "T07: Lệnh 'rsync --server' trong whitelist được thực thi thành công"
    else
        fail "T07: Lệnh 'rsync --server' bị từ chối hoặc lỗi (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T08: Lệnh prune-backups:<N> hợp lệ -> Chấp nhận thực thi và dọn dẹp
# ========================================================
t08_prune_backups_allowed() {
    local sandbox
    sandbox="$(make_sandbox)"
    # Tạo fake backup file cũ (giả lập mtime > 7 ngày)
    touch -d "10 days ago" "${sandbox}/srv/backup/backup_old_20261110_010000.tar.gz" 2>/dev/null || \
        touch -t 202611100100.00 "${sandbox}/srv/backup/backup_old_20261110_010000.tar.gz" 2>/dev/null || \
        touch "${sandbox}/srv/backup/backup_old_20261110_010000.tar.gz"
    touch "${sandbox}/srv/backup/backup_new_20261124_020000.tar.gz"

    local rc=0
    local out
    out="$(ALLOWED_DIR="${sandbox}/srv/backup" \
        SSH_ORIGINAL_COMMAND="prune-backups:7" \
        bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?

    # Kiểm tra lệnh không hợp lệ (chữ thay vì số) bị từ chối
    local rc_bad=0
    SSH_ORIGINAL_COMMAND="prune-backups:abc" ALLOWED_DIR="${sandbox}/srv/backup" \
        bash "${WRAPPER_SCRIPT}" >/dev/null 2>&1 || rc_bad=$?

    # Kiểm tra bash -s bị từ chối 100% (chống RCE stdin)
    local rc_bash_s=0
    SSH_ORIGINAL_COMMAND="bash -s -- ${sandbox}/srv/backup 7" ALLOWED_DIR="${sandbox}/srv/backup" \
        bash "${WRAPPER_SCRIPT}" >/dev/null 2>&1 || rc_bash_s=$?

    rm -rf "${sandbox}"

    if [[ $rc -eq 0 && $rc_bad -ne 0 && $rc_bash_s -ne 0 ]]; then
        pass "T08: Lệnh 'prune-backups:<N>' hoạt động chuẩn, validate regex số nguyên và cấm tuyệt đối bash -s"
    else
        fail "T08: Kiểm tra prune-backups thất bại (rc=$rc, rc_bad=$rc_bad, rc_bash_s=$rc_bash_s, out=$out)"
    fi
}

# ========================================================
# T09: [NEGATIVE TEST] find -exec id \; bị từ chối 100% (Triệt tiêu RCE)
# ========================================================
t09_find_exec_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="find /srv/backup -exec id \;" \
        bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "LỖI: Lệnh không nằm trong danh mục cho phép"; then
        pass "T09: Lệnh 'find -exec id \;' bị từ chối với exit 1 (rơi vào catch-all *, triệt tiêu RCE)"
    else
        fail "T09: 'find -exec id \;' không bị từ chối đúng chuẩn (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T10: [NEGATIVE TEST] ls /srv/backup; whoami bị từ chối 100%
# ========================================================
t10_ls_semicolon_command_chain_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="ls /srv/backup; whoami" \
        bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "LỖI: Lệnh không nằm trong danh mục cho phép"; then
        pass "T10: Lệnh nối 'ls /srv/backup; whoami' bị từ chối với exit 1 (rơi vào catch-all *)"
    else
        fail "T10: 'ls /srv/backup; whoami' không bị từ chối đúng chuẩn (rc=$rc, out=$out)"
    fi
}

# ========================================================
# T11: [NEGATIVE TEST] ls generic /srv/backup bị từ chối (bắt buộc dùng list-backups)
# ========================================================
t11_generic_ls_rejected() {
    local rc=0
    local out
    out="$(SSH_ORIGINAL_COMMAND="ls /srv/backup" \
        bash "${WRAPPER_SCRIPT}" 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]] && echo "${out}" | grep -qi "LỖI: Lệnh không nằm trong danh mục cho phép"; then
        pass "T11: Lệnh generic 'ls /srv/backup' bị từ chối với exit 1 (chỉ cho phép lệnh cố định 'list-backups')"
    else
        fail "T11: 'ls /srv/backup' không bị từ chối (rc=$rc, out=$out)"
    fi
}

# ========================================================
# Main
# ========================================================
echo "========================================"
echo " Public Tests — backup-ssh-restriction.sh"
echo "========================================"

t01_interactive_shell_rejected
t02_path_traversal_rejected
t03_unwhitelisted_commands_rejected
t04_dangerous_command_rejected
t05_list_backups_success
t06_list_backups_empty_dir
t07_rsync_command_allowed
t08_prune_backups_allowed
t09_find_exec_rejected
t10_ls_semicolon_command_chain_rejected
t11_generic_ls_rejected

echo "========================================"
echo " Kết quả: ${PASS} PASS / ${FAIL} FAIL"
echo "========================================"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
