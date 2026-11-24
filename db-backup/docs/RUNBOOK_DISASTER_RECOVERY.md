# Sổ Tay Khắc Phục Sự Cố & Vận Hành Sao Lưu (Disaster Recovery Runbook)

> **Dự án:** Hệ thống dịch vụ Web & CSDL `appdb` / `labapp` trên hạ tầng Linux GCP  
> **Phụ trách:** Thành viên TV4 (Bảo) — Phụ trách CSDL, Chiến lược Sao lưu/Khôi phục & Tự động hóa  
> **Cập nhật:** 2026-11-24 (Phiên bản v5.1 — Triệt tiêu RCE SSH & Hỗ trợ CSDL TV3)  
> **Tài liệu tham chiếu:** Mục 7 Báo cáo Đồ án Linux HCMUS

---

## 1. Kiến Trúc Sao Lưu 3-2-1 Rút Gọn (Lightweight 3-2-1 Backup)

Mô hình triển khai tuân thủ nguyên tắc sao lưu tiêu chuẩn công nghiệp:

```
[ Tier 1: Live Data ]
lab-web (10.10.0.10)
├── PostgreSQL DB live (localhost:5432, appdb / labapp)
└── /srv/data (Web content & static assets)
        │
        ▼ (backup.sh hàng ngày lúc 02:00 hoặc thủ công)
[ Tier 2: Local Copy ]
lab-web (10.10.0.10)
└── /var/backups/labapp/backup_YYYYMMDD_HHMMSS.tar.gz (mode 700, retention 7 ngày)
        │
        ▼ (rsync over SSH ed25519 với forced-command wrapper)
[ Tier 3: Off-site / Isolated Copy ]
lab-bkp (10.10.0.20)
└── /srv/backup/backup_YYYYMMDD_HHMMSS.tar.gz (user: backup, retention 7 ngày)
```

- **3 bản sao dữ liệu (3 Copies):**
  1. Bản hoạt động trực tiếp (Live): PostgreSQL CSDL `appdb` + thư mục `/srv/data` trên `lab-web`.
  2. Bản lưu trữ cục bộ (Local): File `.tar.gz` tại `/var/backups/labapp/` trên `lab-web` giúp khôi phục tức thời khi lỗi logic/thao tác nhầm.
  3. Bản lưu trữ từ xa (Remote): File `.tar.gz` tại `/srv/backup/` trên máy chủ độc lập `lab-bkp`.
- **2 loại phương tiện / đĩa (2 Media Types):**
  - Đĩa Persistent Disk của VM1 (`lab-web-data`) gắn tại `/srv/data`.
  - Đĩa Persistent Disk riêng biệt của VM2 (`lab-bkp-data`) gắn tại `/srv/backup`.
- **1 bản cách ly mạng (1 Off-site/Isolated Host):**
  - Máy chủ `lab-bkp` (10.10.0.20) tách rời, nằm trong VPC internal, firewall chỉ mở SSH nội bộ từ `lab-web`.

---

## 2. Nguyên Tắc Đặc Quyền Tối Thiểu (Principle of Least Privilege)

Mọi thành phần trong chuỗi sao lưu được phân quyền chặt chẽ:

| Thực thể | Quyền hạn áp dụng | Lý do & Cơ chế bảo mật |
|---|---|---|
| PostgreSQL Role `appuser` (TV3) | Chỉ cấp `CONNECT` trên DB `appdb`, `USAGE/CREATE` trên schema `public` | Thu hồi toàn bộ quyền superuser; ngăn chặn đọc/ghi chéo các database khác (`labapp`, `postgres`) |
| PostgreSQL Role `labapp_user` | Chỉ cấp `CONNECT` trên DB `labapp`, `USAGE/CREATE` trên schema `public` | Cách ly hoàn toàn giữa 2 database trên cùng cụm |
| File cấu hình `/etc/labapp/db.env` | Owner `appuser:appuser` (hoặc `root:root`), quyền `chmod 600` | Chỉ user được phân quyền đọc được; ngăn người dùng không đặc quyền đọc trộm mật khẩu DB |
| Thư mục `/var/backups/labapp` | Owner `root:root`, quyền `chmod 700` | Ngăn chặn các tiến trình/user khác đọc trộm dữ liệu dump |
| User `backup` trên `lab-bkp` | Không cấp quyền `sudo`, shell `/bin/bash` gắn forced-command | Chỉ dùng làm tài khoản nhận và dọn dẹp dữ liệu theo whitelist |
| Thư mục `/srv/backup` | Owner `backup:backup`, quyền `chmod 750` | Cách ly hoàn toàn dữ liệu sao lưu trên máy chủ lưu trữ |
| SSH Key `/etc/labapp/.ssh/id_ed25519` | Keypair Ed25519 riêng, quyền `chmod 600` | Tách biệt với SSH key cá nhân của các thành viên |
| SSH Forced Command Wrapper | `backup-ssh-restriction.sh` gắn trong `authorized_keys` | Chặn tương tác shell; chỉ cho phép `rsync --server`, `list-backups` và `prune-backups:<N>` |

---

## 3. Quản Lý & Cách Ly Secret

1. **Tuyệt đối không hard-code credential trong script:**
   - Script `backup.sh` và `restore.sh` nạp thông số qua biến môi trường từ `/etc/labapp/db.env`.
   - Script `setup_db.sh` hỗ trợ truyền mật khẩu qua cờ `-p` hoặc nạp từ file `.env` chuẩn.
2. **Không làm lộ mật khẩu trên tiến trình hệ thống (`ps aux`):**
   - Không truyền cờ `--password` hoặc mật khẩu dạng tham số dòng lệnh vào `pg_dump`/`psql`.
   - Sử dụng biến `PGPASSWORD` được gán scoped cục bộ trong lệnh:
     ```bash
     PGPASSWORD="${DB_PASSWORD}" pg_dump -h "${DB_HOST}" -U "${DB_USER}" ...
     ```
3. **Bộ nhớ tạm thời an toàn:**
   - Dữ liệu dump xuất ra thư mục tạm `TMP_DIR=$(mktemp -d)` và được `trap cleanup EXIT` xóa sạch ngay khi script kết thúc (kể cả khi thành công hoặc gặp lỗi).

---

## 4. Kiểm Tra Dung Lượng Đĩa Trước Khi Chạy (Pre-flight Disk Check)

Để tránh tình trạng ghi đầy đĩa làm sập dịch vụ CSDL đang chạy, `backup.sh` tính toán trước dung lượng cần thiết:

$$\text{Dung lượng yêu cầu} = (\text{DB Size} \times 2) + \text{Web Size} + \text{MIN\_FREE\_MB}$$

*Hệ số 2 cho DB nhằm dự trù dung lượng cho file SQL dump tạm thời và file nén tar.gz.*

- **Ví dụ tính toán thực tế:**
  - Dung lượng CSDL `appdb`: ~8.8 MB
  - Dung lượng thư mục web `/srv/data`: ~0.03 MB
  - Dự phòng an toàn tối thiểu (`MIN_FREE_MB`): 100 MB
  - $\rightarrow \text{Yêu cầu} \approx (8.8 \times 2) + 0.03 + 100 \approx 117.6\text{ MB}$.
  - Nếu phân vùng `/var/backups/labapp` còn trống < ngưỡng yêu cầu: script lập tức dừng lại (`die`), ghi log cảnh báo và không chạm vào DB.

---

## 5. Kịch Bản Khôi Phục 1: Hỏng Dữ Liệu CSDL Cục Bộ (Local Corruption)

### 5.1. Triệu chứng
- Bảng dữ liệu bị xóa nhầm hoặc hỏng logic do lỗi người dùng.
- Thư mục web `/srv/data` bị lỗi hoặc mất file.
- Máy chủ `lab-web` vẫn hoạt động bình thường, các bản backup cục bộ tại `/var/backups/labapp/` còn nguyên vẹn.

### 5.2. Các bước thực hiện khôi phục
```bash
# Bước 1: Liệt kê các bản backup cục bộ khả dụng
ls -lh /var/backups/labapp/backup_*.tar.gz

# Bước 2: Dừng ứng dụng web tạm thời để tránh xung đột dữ liệu mới
sudo systemctl stop app.service

# Bước 3: Chạy script khôi phục chỉ định bản backup mong muốn
sudo /usr/local/bin/restore.sh -f /var/backups/labapp/backup_YYYYMMDD_HHMMSS.tar.gz

# Bước 4: Khởi động lại ứng dụng
sudo systemctl start app.service

# Bước 5: Kiểm tra trạng thái ứng dụng và endpoint
sudo systemctl status app.service
curl -i http://127.0.0.1:8000/items
```

---

## 6. Kịch Bản Khôi Phục 2: Sập Toàn Bộ Server Chính (Disaster Recovery Scenario 2)

### 6.1. Triệu chứng
- Máy chủ `lab-web` hỏng phần cứng/ổ đĩa hoặc toàn bộ bản sao lưu cục bộ tại `/var/backups/labapp/` bị xóa sạch.
- Bản sao lưu hợp lệ duy nhất còn lại nằm trên máy chủ dự phòng `lab-bkp` (10.10.0.20).

### 6.2. Cơ chế phục hồi tự động qua SSH Channel
- Script `restore.sh` tự động phát hiện thư mục local rỗng và gửi lệnh non-interactive:
  ```bash
  ssh -i /etc/labapp/.ssh/id_ed25519 backup@10.10.0.20 "list-backups" | head -n 1
  ```
- Phía `lab-bkp`, wrapper `backup-ssh-restriction.sh` tự động liệt kê các file `.tar.gz` mới nhất.
- Client kéo archive mới nhất về qua `rsync` an toàn và tiến hành giải nén, nạp CSDL và khôi phục web files.

### 6.3. Quy trình thực hiện trên máy chủ mới / khôi phục sau sự cố
```bash
# Bước 1: Khởi tạo/cấu hình CSDL appdb và role appuser bằng setup_db.sh
APP_DB_PASSWORD=$(sudo grep -E '^DB_PASSWORD=' /opt/app/.env | cut -d'=' -f2-)
sudo /usr/local/bin/setup_db.sh -d appdb -u appuser -p "${APP_DB_PASSWORD}" -e /etc/labapp/db.env -o appuser:appuser

# Bước 2: Chạy restore.sh ở chế độ tự động kéo dữ liệu từ xa (Remote Pull)
# Khi không truyền cờ -f và local không có archive, script tự động pull bản mới nhất từ 10.10.0.20
sudo /usr/local/bin/restore.sh

# Bước 3: Khởi động lại app và kiểm chứng
sudo systemctl restart app.service
curl -i http://127.0.0.1:8000/items
```

---

## 7. Danh Mục Bằng Chứng Nghiệm Thu (Evidence Checklist)

Toàn bộ các bằng chứng dưới đây đã được kiểm chứng và đạt kết quả thực tế 100% trên cụm lab GCP:

- [x] **E1 — Sao lưu thành công (`backup.sh`):**
  - Tạo file archive cục bộ: `/var/backups/labapp/backup_20261124_145218.tar.gz`.
  - Tự động rsync sang `lab-bkp:/srv/backup/` với tốc độ ổn định, dung lượng nén tối ưu.
- [x] **E2 — Retention an toàn (`prune-backups:<DAYS>`):**
  - Gọi remote SSH retention với lệnh `prune-backups:7`, tự động xóa các file quá hạn trên `lab-bkp` mà không sử dụng `bash -s`.
- [x] **E3 — Tự động hóa Systemd Timer:**
  - `labapp-backup.timer` kích hoạt hàng ngày lúc 02:00, cấu hình `Persistent=true`.
- [x] **E4 — DR Scenario 2 (Mất sạch Local Backup & Web File):**
  - Xóa sạch `/var/backups/labapp/*` và `/srv/data/webfiles/index.html`.
  - Chạy `sudo /usr/local/bin/restore.sh`: Tự động gửi `list-backups` sang `lab-bkp`, kéo archive mới nhất về và phục hồi 100% dữ liệu.
- [x] **E5 — Tính toàn vẹn Web Content:**
  - File `/srv/data/webfiles/index.html` được khôi phục nguyên vẹn:
    `<h1>HCMUS Linux Final Project - Web Portal (TV3 + TV4)</h1>`
- [x] **E6 — Tính toàn vẹn Ứng dụng Web TV3:**
  - Endpoint `curl -i http://127.0.0.1:8000/items` trả về `HTTP/1.1 200 OK` với đủ 4 bản ghi JSON.
- [x] **E7 — Cô lập CSDL (Database Isolation):**
  - Database `appdb` chứa 4 bản ghi phục vụ TV3.
  - Database `labapp` cũ chứa 3 bản ghi lịch sử, hoàn toàn không bị ảnh hưởng hay ghi đè khi restore `appdb`.
- [x] **E8 — An toàn Mạng & Đặc quyền tối thiểu:**
  - Cổng PostgreSQL 5432 chỉ lắng nghe duy nhất trên `127.0.0.1`.
  - File `/etc/labapp/db.env` phân quyền `chmod 600 appuser:appuser`.
  - Quyền các script quản trị trong `/usr/local/bin/` phân quyền `chmod 750 root:root`.

---

## 8. Các Câu Hỏi Vấn Đáp Thường Gặp (Defense Q&A)

### Câu 1: Tại sao không dùng lệnh cron truyền thống (`crontab -e`) mà lại dùng systemd timer?
> **Trả lời:** `systemd timer` có nhiều ưu điểm vượt trội:
> 1. Có tính năng `Persistent=true`: nếu server bị tắt hoặc treo lúc 02:00, ngay khi khởi động lại systemd sẽ kích hoạt chạy bù ngay, trong khi cron sẽ bỏ qua luôn.
> 2. Quản lý log tập trung: toàn bộ stdout/stderr tích hợp tự động vào `journalctl`, dễ truy vết lỗi.
> 3. Tận dụng cơ chế bảo mật process của systemd: có thể áp dụng `ProtectSystem=strict`, `NoNewPrivileges=yes`, `PrivateTmp=yes` trực tiếp trong service unit.

### Câu 2: Biến `PGPASSWORD` được truyền vào `pg_dump` như thế nào để không bị lộ trên tiến trình `ps aux`?
> **Trả lời:** Chúng em không dùng `export PGPASSWORD=...` ở cấp độ toàn shell. Mật khẩu được truyền scoped theo cú pháp:
> `PGPASSWORD="${DB_PASSWORD}" pg_dump ...`
> Cú pháp này chỉ truyền biến môi trường vào bảng biến môi trường của tiến trình con `pg_dump`, không nằm trên dòng lệnh (command line arguments), do đó lệnh `ps aux` hoặc `ps -ef` chỉ nhìn thấy `pg_dump -h 127.0.0.1 ...` mà không thấy giá trị mật khẩu.

### Câu 3: Kênh rsync sang `lab-bkp` được bảo vệ như thế nào trước nguy cơ chiếm đoạt quyền (RCE)?
> **Trả lời:**
> 1. Chỉ dùng SSH keypair ed25519 riêng biệt cho backup, không dùng chung key cá nhân.
> 2. Phía `lab-bkp` cấu hình forced-command `backup-ssh-restriction.sh` trong `~backup/.ssh/authorized_keys` kèm các cờ `no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty`.
> 3. **Triệt tiêu hoàn toàn RCE qua stdin:** Tuyệt đối không dùng `bash -s --`. Mọi tác vụ được chuyển thành các lệnh cố định: `list-backups` và `prune-backups:<N>`. Wrapper tự kiểm tra regex `^[0-9]+$` đối với số ngày và tự thực thi `find ... -delete` cục bộ. Mọi yêu cầu mở interactive shell hoặc injection đều bị từ chối với exit code 1.

### Câu 4: Làm thế nào để đảm bảo khi khôi phục database `appdb` không làm hỏng hoặc xóa nhầm database `labapp` cũ?
> **Trả lời:**
> 1. Trong `restore.sh`, kết nối psql được chỉ định tường minh qua cờ `-d "${DB_NAME}"`. Trong PostgreSQL, phiên làm việc được gắn chặt và cô lập 100% trong database này; các lệnh DDL `DROP TABLE` và truy vấn catalog `pg_tables` chỉ tác động trong phạm vi database đó.
> 2. Role ứng dụng (`appuser`) được thiết lập theo nguyên tắc Least Privilege: `REVOKE ALL ON SCHEMA public FROM PUBLIC` và chỉ được cấp quyền trong `appdb`, hoàn toàn không có quyền `CONNECT` tới `labapp`.

### Câu 5: Nếu `lab-bkp` bị mất mạng giữa chừng khi đang chạy `backup.sh` thì sao?
> **Trả lời:** Script sử dụng cờ bảo vệ `ARCHIVE_OK=true`. Sau khi đóng gói xong `.tar.gz` cục bộ, cờ này được bật. Nếu bước `sync_to_remote` hoặc lệnh SSH retention remote thất bại:
> 1. Script ghi log lỗi/cảnh báo rõ ràng.
> 2. Hàm `cleanup()` kiểm tra `ARCHIVE_OK=true` nên **giữ nguyên 100% bản backup cục bộ** an toàn trên đĩa, không xóa nhầm dữ liệu.
