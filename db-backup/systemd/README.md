# Hướng Dẫn Vận Hành Systemd Timer — labapp-backup

Thư mục này chứa file cấu hình systemd service và timer cho tác vụ tự động sao lưu định kỳ của `labapp` vào lúc **02:00 sáng hàng ngày**.

## 1. Thành phần
- `labapp-backup.service`: Unit service dạng `oneshot` kích hoạt script `/opt/labapp/db-backup/scripts/backup.sh`, áp dụng sandbox hardening (`ProtectSystem=strict`, `NoNewPrivileges=yes`, `PrivateTmp=yes`, `ReadWritePaths=...`).
- `labapp-backup.timer`: Timer chạy định kỳ lúc `02:00:00`, có `Persistent=true` đảm bảo nếu máy tắt vào lúc 02:00 thì backup sẽ chạy bù ngay sau khi khởi động lại.

## 2. Quy trình Cài đặt & Kích hoạt (5 lệnh chuẩn)
Thực thi trên máy chủ `lab-web` (10.10.0.10):

```bash
# 1. Sao chép các unit file vào thư mục systemd của hệ thống
sudo cp db-backup/systemd/labapp-backup.* /etc/systemd/system/

# 2. Nạp lại cấu hình systemd daemon
sudo systemctl daemon-reload

# 3. Kích hoạt và khởi chạy timer ngay lập tức
sudo systemctl enable --now labapp-backup.timer

# 4. Kiểm tra lịch chạy timer
systemctl list-timers --all | grep labapp-backup

# 5. Kiểm tra trạng thái hoạt động của timer
systemctl status labapp-backup.timer
```

## 3. Kiểm tra Logs & Debug
```bash
# Xem log chạy của backup service
sudo journalctl -u labapp-backup.service -e --no-pager

# Thử nghiệm chạy thủ công 1 lần qua systemd (không chờ tới 02:00)
sudo systemctl start labapp-backup.service
sudo systemctl status labapp-backup.service
```

