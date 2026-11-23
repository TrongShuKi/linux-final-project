#!/usr/bin/env bash
# test_backup.sh — Bộ test công khai (Public Tests) cho backup.sh
# Chạy: bash test_backup.sh
# Không cần PostgreSQL/rsync thật; mọi lệnh hệ thống đều được stub qua PATH giả.
#
# Tiêu chí PASS: tất cả test in OK, script thoát exit 0.
# Tiêu chí FAIL: bất kỳ test nào in FAIL, script thoát exit 1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/../scripts/backup.sh"
PASS=0
FAIL=0

# ---- Màu sắc terminal ----
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

pass() { echo -e "${GREEN}  OK${NC}  $1"; ((PASS++)); }
fail() { echo -e "${RED} FAIL${NC}  $1"; ((FAIL++)); }

# ---- Thiết lập môi trường giả lập root nếu đang chạy non-root (CI/Sandbox) ----
if [[ "${EUID}" -ne 0 ]]; then
    if command -v gcc >/dev/null 2>&1; then
        cat << 'CSRC' | gcc -shared -fPIC -o /tmp/libfakeuid.so -xc - 2>/dev/null || true
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/types.h>
int getresuid(uid_t *ruid, uid_t *euid, uid_t *suid) {
    if (ruid) *ruid = 0;
    if (euid) *euid = 0;
    if (suid) *suid = 0;
    return 0;
}
uid_t geteuid(void) { return 0; }
uid_t getuid(void) { return 0; }
CSRC
        if [[ -f /tmp/libfakeuid.so ]]; then
            export LD_PRELOAD=/tmp/libfakeuid.so
        fi
    fi
fi

# ---- Tiện ích tạo môi trường sandbox ----
make_sandbox() {
    local sandbox
    sandbox="$(mktemp -d)"
    # Tạo ENV_FILE hợp lệ
    mkdir -p "${sandbox}/etc/labapp"
    cat > "${sandbox}/etc/labapp/db.env" <<'ENV'
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=labapp
DB_USER=labapp_user
DB_PASSWORD=test_password_123
DATABASE_URL=postgresql://labapp_user:test_password_123@127.0.0.1:5432/labapp
ENV
    chmod 600 "${sandbox}/etc/labapp/db.env"

    # Tạo các thư mục cần thiết
    mkdir -p "${sandbox}/srv/data/webfiles"
    echo "dummy_web_content" > "${sandbox}/srv/data/webfiles/index.html"
    mkdir -p "${sandbox}/srv/data/backups"
    mkdir -p "${sandbox}/srv/backup"
    mkdir -p "${sandbox}/var/log/labapp"
    mkdir -p "${sandbox}/bin"

    echo "${sandbox}"
}

# ---- Tạo stub commands (giả lập pg_dump, rsync, ssh thành công) ----
make_stubs_success() {
    local stub_dir="$1"
    mkdir -p "${stub_dir}"

    # pg_dump stub: tạo file SQL giả
    cat > "${stub_dir}/pg_dump" <<'SH'
#!/usr/bin/env bash
# Parse -f argument
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-f" ]]; then
        echo "-- pg_dump stub output" > "$2"
        shift 2
    else
        shift
    fi
done
exit 0
SH

    # psql stub: trả về 1048576 (1 MB giả) khi hỏi pg_database_size
    cat > "${stub_dir}/psql" <<'SH'
#!/usr/bin/env bash
echo "1048576"
exit 0
SH

    # rsync stub: thành công
    cat > "${stub_dir}/rsync" <<'SH'
#!/usr/bin/env bash
echo "[stub rsync] OK: $*"
exit 0
SH

    # ssh stub: thành công, có ghi nhận stdin và tham số vào SSH_CAPTURE_LOG nếu được set
    cat > "${stub_dir}/ssh" <<'SH'
#!/usr/bin/env bash
echo "[stub ssh] OK: $*"
if [[ -n "${SSH_CAPTURE_LOG:-}" ]]; then
    echo "ARGS: $*" >> "${SSH_CAPTURE_LOG}"
    cat >> "${SSH_CAPTURE_LOG}"
fi
exit 0
SH

    # tar stub: tạo file archive giả
    cat > "${stub_dir}/tar" <<'SH'
#!/usr/bin/env bash
# Tìm -f <output_file> trong args
prev=""
for arg in "$@"; do
    if [[ "${prev}" == "-f" || "${prev}" == *f* && "${prev}" == -* ]]; then
        touch "${arg}" 2>/dev/null || true
        break
    fi
    prev="${arg}"
done
exit 0
SH

    chmod +x "${stub_dir}/pg_dump" "${stub_dir}/psql" \
              "${stub_dir}/rsync" "${stub_dir}/ssh" "${stub_dir}/tar"
}

make_stubs_rsync_fail() {
    local stub_dir="$1"
    make_stubs_success "${stub_dir}"
    cat > "${stub_dir}/rsync" <<'SH'
#!/usr/bin/env bash
echo "[stub rsync] FAIL: simulated error" >&2
exit 1
SH
    chmod +x "${stub_dir}/rsync"
}

make_stubs_pgdump_fail() {
    local stub_dir="$1"
    make_stubs_success "${stub_dir}"
    cat > "${stub_dir}/pg_dump" <<'SH'
#!/usr/bin/env bash
echo "[stub pg_dump] FAIL: simulated connection error" >&2
exit 1
SH
    chmod +x "${stub_dir}/pg_dump"
}

# ===========================================================================
echo ""
echo "====== Public Tests: backup.sh ======"
echo ""

# ---------------------------------------------------------------------------
# T01: script tồn tại và có thể thực thi
# ---------------------------------------------------------------------------
echo "T01: Script tồn tại và có quyền thực thi"
if [[ -f "${BACKUP_SCRIPT}" && -x "${BACKUP_SCRIPT}" ]]; then
    pass "T01"
else
    fail "T01: ${BACKUP_SCRIPT} không tìm thấy hoặc không có +x"
fi

# ---------------------------------------------------------------------------
# T02: bash -n không lỗi cú pháp
# ---------------------------------------------------------------------------
echo "T02: bash -n (kiểm tra cú pháp)"
if bash -n "${BACKUP_SCRIPT}" 2>/dev/null; then
    pass "T02"
else
    fail "T02: bash -n báo lỗi cú pháp"
fi

# ---------------------------------------------------------------------------
# T03: shellcheck -x không lỗi/cảnh báo
# ---------------------------------------------------------------------------
echo "T03: shellcheck -x (không lỗi/cảnh báo)"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x "${BACKUP_SCRIPT}" 2>/dev/null; then
        pass "T03"
    else
        fail "T03: shellcheck tìm thấy lỗi hoặc cảnh báo"
    fi
else
    echo "       [SKIP] shellcheck chưa cài — bỏ qua T03"
    ((PASS++))
fi

# ---------------------------------------------------------------------------
# T04: -h in usage và exit 0
# ---------------------------------------------------------------------------
echo "T04: Flag -h in usage và exit 0"
output="$("${BACKUP_SCRIPT}" -h 2>&1)" ; rc=$?
if [[ ${rc} -eq 0 && "${output}" == *"-e"* && "${output}" == *"-n"* ]]; then
    pass "T04"
else
    fail "T04: -h không exit 0 hoặc thiếu tham số (rc=${rc})"
fi

# ---------------------------------------------------------------------------
# T05: ENV_FILE không tồn tại → die với exit ≠ 0
# ---------------------------------------------------------------------------
echo "T05: ENV_FILE không tồn tại → die"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/nonexistent/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
if [[ ${rc} -ne 0 ]]; then
    pass "T05"
else
    fail "T05: Script không fail khi ENV_FILE không tồn tại (rc=${rc})"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T06: ENV_FILE thiếu biến DB_PASSWORD → die với exit ≠ 0
# ---------------------------------------------------------------------------
echo "T06: ENV_FILE thiếu DB_PASSWORD → die"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
cat > "${sb}/etc/labapp/db.env" <<'ENV'
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=labapp
DB_USER=labapp_user
ENV
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
if [[ ${rc} -ne 0 ]]; then
    pass "T06"
else
    fail "T06: Script không fail khi DB_PASSWORD thiếu (rc=${rc})"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T07: Dry-run (-n) không tạo file dump hay archive
# ---------------------------------------------------------------------------
echo "T07: Dry-run (-n) không tạo file thực"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -n \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
archive_count="$(find "${sb}/srv/data/backups" -name 'backup_*.tar.gz' 2>/dev/null | wc -l)"
if [[ ${rc} -eq 0 && "${archive_count}" -eq 0 ]]; then
    pass "T07"
else
    fail "T07: dry-run tạo ${archive_count} file archive hoặc exit_code=${rc}"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T08: rsync thất bại → exit ≠ 0 VÀ backup local vẫn còn
# ---------------------------------------------------------------------------
echo "T08: rsync thất bại → exit ≠ 0 và backup local được giữ"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_rsync_fail "${stubs}"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
archive_count="$(find "${sb}/srv/data/backups" -name 'backup_*.tar.gz' 2>/dev/null | wc -l)"
if [[ ${rc} -ne 0 && "${archive_count}" -ge 1 ]]; then
    pass "T08"
else
    fail "T08: rc=${rc}, archive_count=${archive_count} (kỳ vọng rc≠0 và count≥1)"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T09: pg_dump thất bại → exit ≠ 0
# ---------------------------------------------------------------------------
echo "T09: pg_dump thất bại → exit ≠ 0"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_pgdump_fail "${stubs}"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
if [[ ${rc} -ne 0 ]]; then
    pass "T09"
else
    fail "T09: Script không fail khi pg_dump lỗi (rc=${rc})"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T10: WEB_DIR rỗng/không tồn tại → log cảnh báo, không fail
# ---------------------------------------------------------------------------
echo "T10: WEB_DIR rỗng/không tồn tại → log cảnh báo, không fail"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/nonexistent_webdir" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>&1 ; rc=$?
if [[ ${rc} -eq 0 ]]; then
    pass "T10"
else
    fail "T10: Script fail khi WEB_DIR không tồn tại (rc=${rc})"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T11: Dung lượng đĩa không đủ → die trước pg_dump (khi không dry-run)
# ---------------------------------------------------------------------------
echo "T11: Dung lượng đĩa không đủ → die trước pg_dump"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
cat > "${stubs}/psql" <<'SH'
#!/usr/bin/env bash
echo "999999999999"
exit 0
SH
chmod +x "${stubs}/psql"
cat > "${stubs}/df" <<'SH'
#!/usr/bin/env bash
printf 'Avail\n1024\n'
exit 0
SH
chmod +x "${stubs}/df"
cat > "${stubs}/pg_dump" <<SH
#!/usr/bin/env bash
echo "ERROR: pg_dump được gọi dù đĩa không đủ!" >&2
touch "${sb}/pg_dump_was_called"
exit 1
SH
chmod +x "${stubs}/pg_dump"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    2>/dev/null ; rc=$?
if [[ ${rc} -ne 0 && ! -f "${sb}/pg_dump_was_called" ]]; then
    pass "T11"
else
    fail "T11: rc=${rc}, pg_dump_called=$(test -f "${sb}/pg_dump_was_called" && echo yes || echo no)"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T12: Tùy chọn không hợp lệ → die với exit ≠ 0
# ---------------------------------------------------------------------------
echo "T12: Tùy chọn không hợp lệ → die"
"${BACKUP_SCRIPT}" -Z 2>/dev/null ; rc=$?
if [[ ${rc} -ne 0 ]]; then
    pass "T12"
else
    fail "T12: Script không fail với tùy chọn không hợp lệ (rc=${rc})"
fi

# ---------------------------------------------------------------------------
# T13: Kiểm tra quyền root (EUID != 0) → die với thông báo lỗi
# ---------------------------------------------------------------------------
echo "T13: Không chạy bằng root (EUID != 0) → die"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
output="$(LD_PRELOAD="" PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" 2>&1)" ; rc=$?
if [[ ${rc} -ne 0 && "${output}" == *"sudo/root"* ]]; then
    pass "T13"
else
    fail "T13: rc=${rc}, output='${output}' (kỳ vọng die vì thiếu root)"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T14: Retention remote truyền đúng tham số BKP_PATH và DAYS cho bash -s qua SSH
# ---------------------------------------------------------------------------
echo "T14: Retention remote truyền đúng tham số BKP_PATH và DAYS cho bash -s"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
ssh_log="${sb}/ssh_capture.log"
SSH_CAPTURE_LOG="${ssh_log}" PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" \
    -r 14 \
    2>/dev/null ; rc=$?
if [[ ${rc} -eq 0 && -f "${ssh_log}" ]]; then
    log_content="$(cat "${ssh_log}")"
    if [[ "${log_content}" == *"bash -s -- ${sb}/srv/backup 14"* && \
          "${log_content}" == *"find \"\${dir}\" -maxdepth 1"* && \
          "${log_content}" == *"rm -f -- \"\${f}\""* ]]; then
        pass "T14"
    else
        fail "T14: Lệnh SSH remote không chứa đúng bash -s hoặc heredoc find/rm"
    fi
else
    fail "T14: rc=${rc}, ssh_log không tồn tại"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T15: Dry-run (-n) khi thiếu đĩa → log cảnh báo và exit 0 (không die)
# ---------------------------------------------------------------------------
echo "T15: Dry-run (-n) khi thiếu đĩa → log cảnh báo và exit 0"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
cat > "${stubs}/psql" <<'SH'
#!/usr/bin/env bash
echo "999999999999"
exit 0
SH
chmod +x "${stubs}/psql"
cat > "${stubs}/df" <<'SH'
#!/usr/bin/env bash
printf 'Avail\n1024\n'
exit 0
SH
chmod +x "${stubs}/df"
output="$(PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -n \
    -e "${sb}/etc/labapp/db.env" \
    -o "${sb}/srv/data/backups" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" 2>&1)" ; rc=$?
if [[ ${rc} -eq 0 && "${output}" == *"CẢNH BÁO (dry-run): dung lượng đĩa không đủ"* ]]; then
    pass "T15"
else
    fail "T15: rc=${rc}, output='${output}'"
fi
rm -rf "${sb}"

# ---------------------------------------------------------------------------
# T16: Dry-run (-n) không tạo thư mục OUT_DIR nếu chưa có
# ---------------------------------------------------------------------------
echo "T16: Dry-run (-n) không tạo thư mục OUT_DIR"
sb="$(make_sandbox)"
stubs="${sb}/stubs"; make_stubs_success "${stubs}"
nonexistent_out="${sb}/nonexistent_out_dir"
PATH="${stubs}:${PATH}" "${BACKUP_SCRIPT}" \
    -n \
    -e "${sb}/etc/labapp/db.env" \
    -o "${nonexistent_out}" \
    -w "${sb}/srv/data/webfiles" \
    -H "127.0.0.1" -p "${sb}/srv/backup" 2>/dev/null ; rc=$?
if [[ ${rc} -eq 0 && ! -d "${nonexistent_out}" ]]; then
    pass "T16"
else
    fail "T16: rc=${rc}, thư mục OUT_DIR bị tạo: $(test -d "${nonexistent_out}" && echo yes || echo no)"
fi
rm -rf "${sb}"

# ===========================================================================
echo ""
echo "====== Kết quả ======"
echo -e "  Passed: ${GREEN}${PASS}${NC}"
echo -e "  Failed: ${RED}${FAIL}${NC}"
echo ""

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
