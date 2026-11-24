#!/usr/bin/env bash
#
# setup_db.sh — Khởi tạo CSDL PostgreSQL và role ứng dụng theo nguyên tắc
# đặc quyền tối thiểu (least privilege) cho Đồ án Linux & Ứng dụng.
# TV4 (Bảo) — db-backup/
#
# Hỗ trợ provisioning nhiều DB (labapp, appdb, ...) độc lập và an toàn.
# Idempotent: chạy lại nhiều lần an toàn, không ghi đè mật khẩu đã có nếu
# không có cờ -p và EnvironmentFile đã tồn tại.
#
# Usage:
#   sudo ./setup_db.sh [-d DB_NAME] [-u DB_USER] [-p DB_PASSWORD] [-e ENV_FILE] [-o ENV_OWNER] [-h]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---- Giá trị mặc định (chỉnh bằng flag khi gọi script) ----
DB_NAME="labapp"
DB_USER="labapp_user"
DB_PASSWORD=""
ENV_FILE="/etc/labapp/db.env"
ENV_OWNER="root:root"
TMP_SQL=""

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "$*"
}

die() {
    log "LỖI: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [-d DB_NAME] [-u DB_USER] [-p DB_PASSWORD] [-e ENV_FILE] [-o ENV_OWNER] [-h]

  -d DB_NAME      Tên database ứng dụng (mặc định: ${DB_NAME})
  -u DB_USER      Tên role/user ứng dụng (mặc định: ${DB_USER})
  -p DB_PASSWORD  Mật khẩu chỉ định (tùy chọn; nếu không truyền sẽ đọc từ ENV_FILE hoặc sinh ngẫu nhiên)
  -e ENV_FILE     Đường dẫn EnvironmentFile chứa connection string (mặc định: ${ENV_FILE})
  -o ENV_OWNER    Owner:group của ENV_FILE (mặc định: ${ENV_OWNER})
  -h              Hiển thị trợ giúp này

Idempotent: tạo role/database/bảng items nếu chưa có; gán quyền least-privilege trên schema public.
EOF
}

cleanup() {
    local exit_code=$?
    if [[ -n "${TMP_SQL}" && -f "${TMP_SQL}" ]]; then
        rm -f "${TMP_SQL}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        log "Script kết thúc với mã lỗi ${exit_code}"
    fi
    exit "${exit_code}"
}
trap cleanup EXIT
trap 'die "Lệnh thất bại ở dòng ${LINENO}"' ERR

while getopts ":d:u:p:e:o:h" opt; do
    case "${opt}" in
        d) DB_NAME="${OPTARG}" ;;
        u) DB_USER="${OPTARG}" ;;
        p) DB_PASSWORD="${OPTARG}" ;;
        e) ENV_FILE="${OPTARG}" ;;
        o) ENV_OWNER="${OPTARG}" ;;
        h) usage; exit 0 ;;
        \?) die "Tùy chọn không hợp lệ: -${OPTARG}" ;;
        :) die "Tùy chọn -${OPTARG} cần tham số" ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || die "Script cần chạy với sudo/root (để ghi ${ENV_FILE})."
command -v psql >/dev/null 2>&1 || die "Không tìm thấy psql. Cài postgresql-client trước."

log "Bắt đầu provisioning: db=${DB_NAME} user=${DB_USER} env_file=${ENV_FILE}"

# ---- Xử lý mật khẩu (ưu tiên: cờ -p > ENV_FILE cũ > sinh ngẫu nhiên) ----
if [[ -n "${DB_PASSWORD}" ]]; then
    DB_PASSWORD="$(printf '%s' "${DB_PASSWORD}" | tr -d '\r')"
    log "Sử dụng mật khẩu được truyền qua tham số -p cho ${DB_USER}."
elif [[ -f "${ENV_FILE}" ]]; then
    log "ENV_FILE đã tồn tại, tái sử dụng mật khẩu hiện có từ ${ENV_FILE}."
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    DB_PASSWORD="${DB_PASSWORD:?Không tìm thấy DB_PASSWORD trong ${ENV_FILE}}"
    DB_PASSWORD="$(printf '%s' "${DB_PASSWORD}" | tr -d '\r')"
else
    DB_PASSWORD="$(openssl rand -base64 24)"
    log "Đã sinh mật khẩu ngẫu nhiên mới cho ${DB_USER}."
fi

# ---- 1. Tạo hoặc cập nhật role ứng dụng (idempotent) ----
TMP_SQL="$(mktemp)"
cat > "${TMP_SQL}" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE "${DB_USER}" WITH LOGIN PASSWORD '${DB_PASSWORD}';
    ELSE
        ALTER ROLE "${DB_USER}" WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
END
\$\$;
SQL

chmod 644 "${TMP_SQL}"
(cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -f "${TMP_SQL}" >/dev/null)
log "Đã đảm bảo role ${DB_USER} tồn tại và mật khẩu đã được cập nhật."

# ---- 2. Tạo database nếu chưa có (idempotent) ----
if ! (cd /tmp && sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'") | grep -q 1; then
    (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";")
    log "Đã tạo database ${DB_NAME} (owner=${DB_USER})."
else
    (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER DATABASE \"${DB_NAME}\" OWNER TO \"${DB_USER}\";" >/dev/null 2>&1 || true)
    log "Database ${DB_NAME} đã tồn tại, đã xác nhận owner=${DB_USER}."
fi

# ---- 3. Thu hồi quyền public, cấp đúng quyền tối thiểu cho app user (Least Privilege) ----
(cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}") <<SQL
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE "${DB_NAME}" TO "${DB_USER}";
GRANT USAGE, CREATE ON SCHEMA public TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${DB_USER}";
SQL
log "Đã thiết lập đặc quyền tối thiểu (least privilege) cho ${DB_USER} trên database ${DB_NAME}."

# ---- 4. Khởi tạo cấu trúc bảng items và dữ liệu mẫu (idempotent) ----
(cd /tmp && PGPASSWORD="${DB_PASSWORD}" psql -h 127.0.0.1 -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1) <<'SQL'
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF (SELECT count(*) FROM items) = 0 THEN
        INSERT INTO items (name) VALUES 
            ('Hệ thống Giám sát Lab HCMUS'),
            ('Cổng Xác thực Nginx Reverse Proxy'),
            ('CSDL PostgreSQL appdb'),
            ('Dịch vụ Tự động Sao lưu Systemd Timer');
    END IF;
END
$$;
SQL
log "Đã đảm bảo bảng items và dữ liệu ban đầu tồn tại trong database ${DB_NAME}."

# ---- 5. Ghi EnvironmentFile cho systemd (db.env) ----
mkdir -p "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<ENVEOF
# Sinh tự động bởi ${SCRIPT_NAME} vào $(date '+%Y-%m-%d %H:%M:%S')
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}
ENVEOF

chmod 600 "${ENV_FILE}"
chown "${ENV_OWNER}" "${ENV_FILE}"
log "Đã ghi ${ENV_FILE} (quyền 600, owner=${ENV_OWNER})."

log "Provisioning database ${DB_NAME} hoàn tất thành công."
