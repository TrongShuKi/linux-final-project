#!/usr/bin/env bash
#
# restore.sh — Khôi phục CSDL PostgreSQL và dữ liệu web từ bản sao lưu .tar.gz.
# Hỗ trợ tự động lấy bản mới nhất tại local hoặc pull từ máy chủ backup (lab-bkp).
# TV4 (Bảo) — db-backup/
#
# Usage:
#   ./restore.sh [-e ENV_FILE] [-f ARCHIVE_FILE] [-w WEB_DIR] [-d BACKUP_DIR] [-h]
#

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---- Hằng số & Giá trị mặc định ----
LOG_FILE="/var/log/labapp/restore.log"
ENV_FILE="/etc/labapp/db.env"
WEB_DIR="/srv/data"
LOCAL_BACKUP_DIR="/var/backups/labapp"
BKP_HOST="10.10.0.20"
BKP_PATH="/srv/backup"
SSH_KEY="/etc/labapp/.ssh/id_ed25519"

ARCHIVE_PATH=""
TMP_DIR=""

# Biến kết nối DB (nạp từ ENV_FILE)
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
Sử dụng: ${SCRIPT_NAME} [TÙY CHỌN]

Tùy chọn:
  -e FILE    Đường dẫn file biến môi trường DB (mặc định: ${ENV_FILE})
  -f FILE    Đường dẫn file sao lưu (.tar.gz) cần khôi phục
  -w DIR     Thư mục dữ liệu web đích (mặc định: ${WEB_DIR})
  -d DIR     Thư mục chứa bản sao lưu cục bộ (mặc định: ${LOCAL_BACKUP_DIR})
  -h         Hiển thị trợ giúp này và thoát

Ví dụ:
  ${SCRIPT_NAME} -f /var/backups/labapp/backup_20261124_020000.tar.gz
  ${SCRIPT_NAME} (tự động chọn bản mới nhất cục bộ hoặc kéo từ lab-bkp)
EOF
    exit 0
}

cleanup() {
    local exit_code=$?
    if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        log "Quy trình khôi phục kết thúc với mã lỗi ${exit_code}"
    fi
}

trap cleanup EXIT
trap 'die "Lệnh thất bại ở dòng ${LINENO}"' ERR

check_dependencies() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Script phải được chạy bằng quyền root (sudo)."
    fi
    local deps=(tar psql rsync ssh awk)
    local dep
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" >/dev/null 2>&1; then
            die "Không tìm thấy công cụ phụ thuộc bắt buộc: ${dep}"
        fi
    done
}

load_env() {
    [[ -f "${ENV_FILE}" ]] || die "Không tìm thấy file môi trường: ${ENV_FILE}"
    [[ -r "${ENV_FILE}" ]] || die "Không có quyền đọc file môi trường: ${ENV_FILE}"

    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    [[ -n "${DB_HOST:-}" ]]     || die "Thiếu DB_HOST trong ${ENV_FILE}"
    [[ -n "${DB_PORT:-}" ]]     || die "Thiếu DB_PORT trong ${ENV_FILE}"
    [[ -n "${DB_NAME:-}" ]]     || die "Thiếu DB_NAME trong ${ENV_FILE}"
    [[ -n "${DB_USER:-}" ]]     || die "Thiếu DB_USER trong ${ENV_FILE}"
    [[ -n "${DB_PASSWORD:-}" ]] || die "Thiếu DB_PASSWORD trong ${ENV_FILE}"
}

get_archive() {
    if [[ -n "${ARCHIVE_PATH}" ]]; then
        [[ -f "${ARCHIVE_PATH}" ]] || die "File archive '${ARCHIVE_PATH}' không tồn tại."
        [[ -r "${ARCHIVE_PATH}" ]] || die "Không có quyền đọc file archive '${ARCHIVE_PATH}'."
        log "Sử dụng archive chỉ định: ${ARCHIVE_PATH}"
        return 0
    fi

    # Không có -f: Tìm bản mới nhất ở local
    local local_archive
    local_archive="$(find "${LOCAL_BACKUP_DIR}" -maxdepth 1 -name 'backup_*.tar.gz' 2>/dev/null | sort -r | head -n 1 || true)"

    if [[ -n "${local_archive}" && -f "${local_archive}" ]]; then
        ARCHIVE_PATH="${local_archive}"
        log "Đã tự động chọn bản backup cục bộ mới nhất: ${ARCHIVE_PATH}"
        return 0
    fi

    log "Không tìm thấy backup cục bộ tại ${LOCAL_BACKUP_DIR}, thử kéo từ remote ${BKP_HOST}:${BKP_PATH}..."
    local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
    if [[ -f "${SSH_KEY}" ]]; then
        ssh_opts+=(-i "${SSH_KEY}")
    fi

    local remote_file
    # shellcheck disable=SC2029
    remote_file="$(ssh -n "${ssh_opts[@]}" "backup@${BKP_HOST}" "list-backups" 2>/dev/null | head -n 1 || true)"

    if [[ -z "${remote_file}" ]]; then
        die "Không tìm thấy bản backup nào ở cả cục bộ lẫn máy chủ từ xa."
    fi

    local remote_name
    remote_name="$(basename "${remote_file}")"
    log "Đang kéo bản backup '${remote_name}' từ ${BKP_HOST}:${BKP_PATH}..."
    rsync -avz -e "ssh ${ssh_opts[*]}" "backup@${BKP_HOST}:${BKP_PATH}/${remote_name}" "${TMP_DIR}/"
    ARCHIVE_PATH="${TMP_DIR}/${remote_name}"

    [[ -f "${ARCHIVE_PATH}" ]] || die "Kéo bản backup từ máy chủ từ xa thất bại."
    log "Kéo bản backup từ xa thành công: ${ARCHIVE_PATH}"
}

verify_archive() {
    log "Kiểm tra tính toàn vẹn của archive: ${ARCHIVE_PATH}"
    [[ -f "${ARCHIVE_PATH}" ]] || die "File archive '${ARCHIVE_PATH}' không tồn tại."
    tar -tzf "${ARCHIVE_PATH}" >/dev/null 2>&1 || die "File archive '${ARCHIVE_PATH}' bị hỏng hoặc không phải tar.gz hợp lệ."
    if ! tar -tzf "${ARCHIVE_PATH}" 2>/dev/null | grep -q "db\.sql"; then
        die "Archive '${ARCHIVE_PATH}' không chứa file db.sql."
    fi
    log "Archive hợp lệ: cấu trúc tar.gz toàn vẹn và có chứa db.sql."
}

terminate_db_connections() {
    log "Ngắt các kết nối đang mở tới database '${DB_NAME}'..."
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
}

restore_database() {
    log "Giải nén archive vào thư mục tạm..."
    tar -xzf "${ARCHIVE_PATH}" -C "${TMP_DIR}"

    local sql_file
    if [[ -f "${TMP_DIR}/db.sql" ]]; then
        sql_file="${TMP_DIR}/db.sql"
    else
        sql_file="$(find "${TMP_DIR}" -name 'db.sql' 2>/dev/null | head -n 1 || true)"
    fi
    [[ -n "${sql_file}" && -f "${sql_file}" ]] || die "Không tìm thấy db.sql sau khi giải nén."

    log "Dọn dẹp các bảng hiện có trong schema public của database '${DB_NAME}' để tránh xung đột..."
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c \
        "DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE'; END LOOP; END \$\$;" >/dev/null 2>&1 || true

    # Loại bỏ các lệnh gán quyền mặc định superuser không thuộc thẩm quyền của DB_USER
    sed -i -E '/ALTER DEFAULT PRIVILEGES FOR ROLE.*postgres/d' "${sql_file}" 2>/dev/null || true

    log "Đang nạp dữ liệu SQL vào database '${DB_NAME}'..."
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${sql_file}"

    # Đảm bảo DB_USER có toàn quyền đọc/ghi trên mọi bảng và sequence sau khi nạp
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c \
        "GRANT ALL ON ALL TABLES IN SCHEMA public TO \"${DB_USER}\"; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO \"${DB_USER}\";" >/dev/null 2>&1 || true

    log "Nạp dữ liệu CSDL hoàn tất thành công."
}

restore_web_content() {
    local web_extracted=""
    if [[ -d "${TMP_DIR}/srv/data" ]]; then
        web_extracted="${TMP_DIR}/srv/data"
    elif [[ -d "${TMP_DIR}/data" ]]; then
        web_extracted="${TMP_DIR}/data"
    fi

    if [[ -n "${web_extracted}" && -d "${web_extracted}" ]]; then
        log "Đang khôi phục nội dung web về ${WEB_DIR}..."
        if ! mkdir -p "${WEB_DIR}" 2>/dev/null; then
            log "CẢNH BÁO: Không thể tạo thư mục đích ${WEB_DIR} (quyền truy cập), bỏ qua khôi phục web."
            return 0
        fi
        if ! rsync -a "${web_extracted}/" "${WEB_DIR}/" 2>/dev/null; then
            log "CẢNH BÁO: rsync nội dung web sang ${WEB_DIR} thất bại (quyền truy cập)."
            return 0
        fi
        log "Khôi phục nội dung web hoàn tất."
    else
        log "CẢNH BÁO: Không tìm thấy dữ liệu web trong archive, bỏ qua khôi phục web."
    fi
}

health_check() {
    log "Thực hiện kiểm tra sau khôi phục (Health check)..."
    local raw_count
    raw_count="$(PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo 0)"
    local table_count
    table_count="$(echo "${raw_count}" | tr -dc '0-9')"
    table_count="${table_count:-0}"

    local web_size=0
    if [[ -d "${WEB_DIR}" ]]; then
        local raw_size
        raw_size="$(du -sb "${WEB_DIR}" 2>/dev/null | awk '{print $1}' || echo 0)"
        web_size="$(echo "${raw_size}" | tr -dc '0-9')"
        web_size="${web_size:-0}"
    fi

    if [[ "${table_count}" -gt 0 ]]; then
        log "[PASS] Health check passed: ${table_count} bảng CSDL public, thư mục web ${web_size} bytes."
    else
        log "[FAIL] Health check failed: số bảng CSDL=${table_count}, dung lượng web=${web_size} bytes."
        exit 1
    fi
}

main() {
    while getopts ":e:f:w:d:h" opt; do
        case "${opt}" in
            e) ENV_FILE="${OPTARG}" ;;
            f) ARCHIVE_PATH="${OPTARG}" ;;
            w) WEB_DIR="${OPTARG}" ;;
            d) LOCAL_BACKUP_DIR="${OPTARG}" ;;
            h) usage ;;
            :) die "Tùy chọn -${OPTARG} yêu cầu tham số." ;;
            \?) die "Tùy chọn không hợp lệ: -${OPTARG}." ;;
        esac
    done
    shift $((OPTIND - 1))

    log "=== Bắt đầu quy trình khôi phục dữ liệu ==="
    check_dependencies
    load_env

    TMP_DIR="$(mktemp -d)"

    get_archive
    verify_archive
    terminate_db_connections
    restore_database
    restore_web_content
    health_check

    log "=== Khôi phục hoàn tất thành công ==="
}

main "$@"
