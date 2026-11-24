#!/usr/bin/env bash
#
# backup.sh — Tự động hóa sao lưu PostgreSQL và thư mục web/app,
# đóng gói nén, đồng bộ rsync sang host backup (lab-bkp) và thực thi retention.
# TV4 (Bảo) — db-backup/
#
# Usage:
#   ./backup.sh [-e ENV_FILE] [-w WEB_DIR] [-o OUT_DIR] [-r DAYS]
#               [-H BKP_HOST] [-p BKP_PATH] [-m MIN_FREE_MB] [-n] [-h]

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---- Hằng số & Giá trị mặc định ----
LOG_FILE="/var/log/labapp/backup.log"

ENV_FILE="/etc/labapp/db.env"
WEB_DIR="/srv/data"
OUT_DIR="/var/backups/labapp"
DAYS=7
BKP_HOST="10.10.0.20"
BKP_PATH="/srv/backup"
MIN_FREE_MB=100
DRY_RUN=false
ARCHIVE_OK=false
SSH_KEY="/etc/labapp/.ssh/id_ed25519"

TMP_DIR=""
ARCHIVE_PATH=""

# Biến kết nối DB (sẽ nạp từ ENV_FILE)
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*"
    printf '%s\n' "${msg}"
    if [[ -d "$(dirname "${LOG_FILE}")" ]]; then
        printf '%s\n' "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

die() {
    log "LỖI: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [-e ENV_FILE] [-w WEB_DIR] [-o OUT_DIR] [-r DAYS]
                 [-H BKP_HOST] [-p BKP_PATH] [-m MIN_FREE_MB] [-n] [-h]

  -e ENV_FILE     Đường dẫn EnvironmentFile chứa thông tin kết nối DB
                  (mặc định: ${ENV_FILE})
  -w WEB_DIR      Thư mục nội dung web/app cần sao lưu cùng
                  (mặc định: ${WEB_DIR})
  -o OUT_DIR      Thư mục lưu trữ bản sao lưu cục bộ
                  (mặc định: ${OUT_DIR})
  -r DAYS         Số ngày lưu trữ trước khi dọn dẹp (retention)
                  (mặc định: ${DAYS})
  -H BKP_HOST     Địa chỉ IP hoặc hostname của máy chủ backup
                  (mặc định: ${BKP_HOST})
  -p BKP_PATH     Thư mục đích trên máy chủ backup
                  (mặc định: ${BKP_PATH})
  -m MIN_FREE_MB  Dung lượng đĩa trống tối thiểu dự phòng (MB)
                  (mặc định: ${MIN_FREE_MB})
  -n              Chế độ chạy thử (dry-run): chỉ kiểm tra, không ghi/xóa thật
  -h              Hiển thị trợ giúp này và thoát
EOF
}

cleanup() {
    local exit_code=$?

    # Dọn dẹp thư mục làm việc tạm thời
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}" || true
    fi

    # Chỉ xóa archive nếu nó dở dang trong quá trình nén (chưa hoàn tất bundle)
    if [[ "${ARCHIVE_OK}" != "true" && -n "${ARCHIVE_PATH}" && -f "${ARCHIVE_PATH}" ]]; then
        log "Xóa archive dở dang: ${ARCHIVE_PATH}"
        rm -f "${ARCHIVE_PATH}" || true
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log "Script kết thúc với mã lỗi ${exit_code}"
    fi
    exit "${exit_code}"
}

trap cleanup EXIT
trap 'die "Lệnh thất bại ở dòng ${LINENO}"' ERR

# ---- Xử lý tùy chọn dòng lệnh ----
while getopts ":e:w:o:r:H:p:m:nh" opt; do
    case "${opt}" in
        e) ENV_FILE="${OPTARG}" ;;
        w) WEB_DIR="${OPTARG}" ;;
        o) OUT_DIR="${OPTARG}" ;;
        r) DAYS="${OPTARG}" ;;
        H) BKP_HOST="${OPTARG}" ;;
        p) BKP_PATH="${OPTARG}" ;;
        m) MIN_FREE_MB="${OPTARG}" ;;
        n) DRY_RUN=true ;;
        h) usage; exit 0 ;;
        \?) die "Tùy chọn không hợp lệ: -${OPTARG}" ;;
        :) die "Tùy chọn -${OPTARG} cần tham số" ;;
    esac
done

# ---- Kiểm tra tính hợp lệ của tham số đầu vào ----
[[ "${DAYS}" =~ ^[0-9]+$ ]] || die "-r DAYS phải là số nguyên dương (nhận: ${DAYS})"
[[ "${MIN_FREE_MB}" =~ ^[0-9]+$ ]] || die "-m MIN_FREE_MB phải là số nguyên dương (nhận: ${MIN_FREE_MB})"
[[ "${BKP_PATH}" =~ ^/[A-Za-z0-9/_.-]+$ ]] || die "-p BKP_PATH không hợp lệ (phải bắt đầu bằng / và không chứa ký tự đặc biệt, nhận: ${BKP_PATH})"
[[ "${BKP_HOST}" =~ ^[A-Za-z0-9.-]+$ ]] || die "-H BKP_HOST không hợp lệ (phải là hostname hoặc IP, nhận: ${BKP_HOST})"

# ---- Hàm kiểm tra sự tồn tại của các công cụ phụ thuộc ----
check_dependencies() {
    local tool
    for tool in pg_dump psql tar rsync ssh df awk; do
        command -v "${tool}" >/dev/null 2>&1 || die "Không tìm thấy công cụ: ${tool}"
    done
    [[ "${EUID}" -eq 0 ]] || die "Script cần chạy với quyền sudo/root"
}

# ---- Hàm nạp và kiểm tra EnvironmentFile ----
load_env() {
    [[ -f "${ENV_FILE}" && -r "${ENV_FILE}" ]] || die "Không tìm thấy hoặc không thể đọc ENV_FILE: ${ENV_FILE}"

    # shellcheck disable=SC1090
    source "${ENV_FILE}"

    [[ -n "${DB_HOST:-}" ]] || die "Thiếu DB_HOST trong ${ENV_FILE}"
    [[ -n "${DB_PORT:-}" ]] || die "Thiếu DB_PORT trong ${ENV_FILE}"
    [[ -n "${DB_NAME:-}" ]] || die "Thiếu DB_NAME trong ${ENV_FILE}"
    [[ -n "${DB_USER:-}" ]] || die "Thiếu DB_USER trong ${ENV_FILE}"
    [[ -n "${DB_PASSWORD:-}" ]] || die "Thiếu DB_PASSWORD trong ${ENV_FILE}"

    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "${OUT_DIR}"
        chmod 700 "${OUT_DIR}"
    fi
}

# ---- Hàm kiểm tra dung lượng đĩa trước khi sao lưu ----
check_disk_space() {
    local db_bytes
    db_bytes="$(PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
        -tAc "SELECT pg_database_size('${DB_NAME}');" 2>/dev/null || echo 0)"
    db_bytes="${db_bytes:-0}"

    local web_bytes=0
    if [[ -d "${WEB_DIR}" ]]; then
        local _du_out
        _du_out="$(du -sb "${WEB_DIR}" 2>/dev/null | awk '{print $1}' || echo 0)"
        web_bytes="${_du_out:-0}"
    fi

    local required_bytes
    required_bytes=$(( (db_bytes * 2) + web_bytes + (MIN_FREE_MB * 1048576) ))

    local check_dir="${OUT_DIR}"
    while [[ ! -d "${check_dir}" && "${check_dir}" != "/" ]]; do
        check_dir="$(dirname "${check_dir}")"
    done

    local available_bytes
    available_bytes="$(df -B1 --output=avail "${check_dir}" 2>/dev/null | tail -n 1 | tr -d ' ' || echo 0)"
    available_bytes="${available_bytes:-0}"

    log "Kiểm tra đĩa: Khả dụng=${available_bytes} bytes, Yêu cầu ước tính=${required_bytes} bytes (DB=${db_bytes}, Web=${web_bytes}, Dự phòng=${MIN_FREE_MB}MB)"

    if [[ ${available_bytes} -lt ${required_bytes} ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "CẢNH BÁO (dry-run): dung lượng đĩa không đủ, nhưng tiếp tục vì đang ở chế độ dry-run."
            return 0
        fi
        die "Dung lượng đĩa tại ${OUT_DIR} (${available_bytes} bytes) không đủ cho backup (yêu cầu tối thiểu: ${required_bytes} bytes)."
    fi
}

# ---- Hàm xuất dữ liệu database bằng pg_dump ----
dump_database() {
    TMP_DIR="$(mktemp -d)"
    log "Bắt đầu pg_dump database '${DB_NAME}' vào ${TMP_DIR}/db.sql..."
    PGPASSWORD="${DB_PASSWORD}" pg_dump \
        -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
        --no-password --clean --if-exists --no-owner --no-acl -Fp -f "${TMP_DIR}/db.sql" "${DB_NAME}"

    local dump_size
    dump_size="$(du -sh "${TMP_DIR}/db.sql" 2>/dev/null | awk '{print $1}' || echo "N/A")"
    log "pg_dump hoàn tất (kích thước: ${dump_size})"
}

# ---- Hàm đóng gói archive nén (.tar.gz) ----
bundle_archive() {
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local archive_name="backup_${timestamp}.tar.gz"
    ARCHIVE_PATH="${OUT_DIR}/${archive_name}"

    log "Bắt đầu đóng gói archive: ${ARCHIVE_PATH}"
    if [[ -d "${WEB_DIR}" && -n "$(ls -A "${WEB_DIR}" 2>/dev/null)" ]]; then
        log "Đóng gói db.sql kèm nội dung thư mục ${WEB_DIR}..."
        tar -czf "${ARCHIVE_PATH}" \
            -C "${TMP_DIR}" db.sql \
            -C "$(dirname "${WEB_DIR}")" "$(basename "${WEB_DIR}")"
    else
        log "CẢNH BÁO: WEB_DIR (${WEB_DIR}) không tồn tại hoặc rỗng, chỉ đóng gói db.sql."
        tar -czf "${ARCHIVE_PATH}" -C "${TMP_DIR}" db.sql
    fi

    ARCHIVE_OK=true

    local archive_size
    archive_size="$(du -sh "${ARCHIVE_PATH}" 2>/dev/null | awk '{print $1}' || echo "N/A")"
    log "Đóng gói hoàn tất: ${ARCHIVE_PATH} (kích thước: ${archive_size})"
}

# ---- Hàm đồng bộ archive sang máy chủ backup qua rsync/SSH ----
sync_to_remote() {
    log "Bắt đầu rsync ${ARCHIVE_PATH} → ${BKP_HOST}:${BKP_PATH}"
    local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
    if [[ -f "${SSH_KEY}" ]]; then
        ssh_opts+=(-i "${SSH_KEY}")
    fi
    if ! rsync -avz \
            -e "ssh ${ssh_opts[*]}" \
            "${ARCHIVE_PATH}" \
            "backup@${BKP_HOST}:${BKP_PATH}/"; then
        die "rsync thất bại — bản backup local được giữ nguyên tại ${ARCHIVE_PATH}"
    fi
    log "rsync hoàn tất thành công."
}

# ---- Hàm thực thi chính sách lưu trữ (retention) ----
enforce_retention() {
    log "Kiểm tra retention local (lưu ${DAYS} ngày) tại ${OUT_DIR}..."
    local local_deleted=0
    local f
    while IFS= read -r -d '' f; do
        log "Xóa backup cũ (local): ${f}"
        rm -f "${f}"
        ((local_deleted++)) || true
    done < <(find "${OUT_DIR}" -maxdepth 1 -name 'backup_*.tar.gz' -mtime "+${DAYS}" -print0 2>/dev/null)
    if [[ ${local_deleted} -eq 0 ]]; then
        log "Không có backup local cũ cần xóa."
    fi

    # Sử dụng lệnh an toàn prune-backups:<DAYS> qua forced-command wrapper,
    # cấm hoàn toàn bash -s và truyền script qua stdin nhằm triệt tiêu lỗ hổng RCE.
    log "Kiểm tra retention remote (lưu ${DAYS} ngày) trên ${BKP_HOST}:${BKP_PATH}..."
    local ssh_opts=(-n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
    if [[ -f "${SSH_KEY}" ]]; then
        ssh_opts+=(-i "${SSH_KEY}")
    fi
    # shellcheck disable=SC2029
    if ! ssh "${ssh_opts[@]}" "backup@${BKP_HOST}" "prune-backups:${DAYS}"; then
        log "CẢNH BÁO: retention remote trên ${BKP_HOST}:${BKP_PATH} thất bại, bỏ qua lần này — bản backup vẫn an toàn ở cả 2 nơi."
    fi
}

# ---- Hàm điều phối chính (main) ----
main() {
    mkdir -p /var/log/labapp 2>/dev/null || true

    log "=== Bắt đầu quy trình sao lưu ==="
    check_dependencies
    load_env
    check_disk_space

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY-RUN: pre-flight checks hoàn tất thành công. Không thực thi dump/bundle/rsync/retention."
        exit 0
    fi

    dump_database
    bundle_archive
    sync_to_remote
    enforce_retention
    log "=== Sao lưu hoàn tất thành công ==="
}

main "$@"
