#!/usr/bin/env bash
#
# setup_db.sh — Khởi tạo CSDL PostgreSQL và role ứng dụng theo nguyên tắc
# đặc quyền tối thiểu (least privilege) cho Đồ án Linux & Ứng dụng.
# TV4 (Bảo) — db-backup/
#
# Idempotent: chạy lại nhiều lần an toàn, không ghi đè mật khẩu đã có nếu
# EnvironmentFile đã tồn tại.
#
# Usage:
#   sudo ./setup_db.sh [-d DB_NAME] [-u DB_USER] [-e ENV_FILE] [-o ENV_OWNER] [-h]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---- Giá trị mặc định (chỉnh bằng flag khi gọi script) ----
DB_NAME="labapp"
DB_USER="labapp_user"
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
Usage: ${SCRIPT_NAME} [-d DB_NAME] [-u DB_USER] [-e ENV_FILE] [-o ENV_OWNER] [-h]

  -d DB_NAME    Tên database ứng dụng (mặc định: ${DB_NAME})
  -u DB_USER    Tên role/user ứng dụng (mặc định: ${DB_USER})
  -e ENV_FILE   Đường dẫn EnvironmentFile chứa connection string
                (mặc định: ${ENV_FILE})
  -o ENV_OWNER  Owner:group của ENV_FILE, dạng "user:group"
                (mặc định: ${ENV_OWNER}; đổi thành user chạy app của TV3,
                vd "appuser:appuser")
  -h            Hiển thị trợ giúp này

Idempotent: tạo role/database nếu chưa có; nếu ENV_FILE đã tồn tại thì
dùng lại mật khẩu cũ thay vì sinh mới.
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

while getopts ":d:u:e:o:h" opt; do
    case "${opt}" in
        d) DB_NAME="${OPTARG}" ;;
        u) DB_USER="${OPTARG}" ;;
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

# ---- Lấy mật khẩu cũ (nếu có) hoặc sinh mới ----
if [[ -f "${ENV_FILE}" ]]; then
    log "ENV_FILE đã tồn tại, tái sử dụng mật khẩu hiện có."
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    DB_PASSWORD="${DB_PASSWORD:?Không tìm thấy DB_PASSWORD trong ${ENV_FILE}}"
else
    DB_PASSWORD="$(openssl rand -base64 24)"
    log "Đã sinh mật khẩu ngẫu nhiên mới cho ${DB_USER}."
fi

# ---- Tạo/cập nhật role (idempotent) ----
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

sudo -u postgres psql -v ON_ERROR_STOP=1 -f "${TMP_SQL}" >/dev/null
log "Đã đảm bảo role ${DB_USER} tồn tại và mật khẩu khớp EnvironmentFile."

# ---- Tạo database nếu chưa có (idempotent) ----
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"
    log "Đã tạo database ${DB_NAME} (owner=${DB_USER})."
else
    log "Database ${DB_NAME} đã tồn tại, bỏ qua bước tạo mới."
fi

# ---- Thu hồi quyền public, cấp đúng quyền tối thiểu cho app user ----
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" <<SQL
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE "${DB_NAME}" TO "${DB_USER}";
GRANT USAGE, CREATE ON SCHEMA public TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${DB_USER}";
SQL
log "Đã cấp quyền tối thiểu cho ${DB_USER} trên database ${DB_NAME}."

# ---- Ghi EnvironmentFile cho systemd (TV3 dùng trong app.service) ----
mkdir -p "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<ENVEOF
# Sinh tự động bởi ${SCRIPT_NAME} vào $(date '+%Y-%m-%d %H:%M:%S')
# KHÔNG commit file này vào git — chỉ commit setup_db.sh và một .env.example
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

log "Hoàn tất. Kiểm chứng bằng:"
log "  sudo -u postgres psql -c '\du'"
log "  sudo -u postgres psql -c '\l'"
log "  ss -tlnp | grep 5432   # phải chỉ thấy 127.0.0.1:5432"

