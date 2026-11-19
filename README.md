# Đồ án cuối kỳ: Hệ điều hành Linux & Ứng dụng

> Skeleton do TV1 tạo. Các mục đánh dấu TODO cần cả nhóm điền trước khi nộp (Mục 1.3 của đề).

## 1. Hướng đồ án đã chọn

TODO: mô tả ngắn hệ thống (reverse proxy → app → CSDL, sao lưu sang VM2, bộ công cụ Bash).

- Trình ảo hóa/hạ tầng: **Google Cloud Platform (GCP)**, thầy Minh đã đồng ý cho dùng thay VirtualBox/VMware.
- Hệ điều hành: Ubuntu 22.04 LTS Server, 2 VM.

## 2. Sơ đồ VM

```
                Internet
                   │ 80/443 (web), 22 và 2222 (SSH)
          ┌────────┴────────┐
          │  lab-web      │  Nginx + App (systemd) + DB (chỉ localhost)
          │  10.10.0.10     │  ổ data: /srv/data
          └────────┬────────┘
                   │ VPC lab-net 10.10.0.0/24 (rsync backup)
          ┌────────┴────────┐
          │  lab-bkp      │  nhận backup
          │  10.10.0.20     │  ổ backup: /srv/backup
          └─────────────────┘
```

## 3. Phân công

| TV | Thành viên | Phần | Thư mục |
|---|---|---|---|
| TV1 | Nguyễn Minh Trọng | Hạ tầng, mạng, SSH, firewall, auditd | `infra/` |
| TV2 | An | Nginx reverse proxy, vhost, TLS tự ký, fail2ban | `proxy/` |
| TV3 | Đạt | Ứng dụng + systemd | `app/` |
| TV4 | Bảo | CSDL, sao lưu/khôi phục | `db-backup/` |
| TV5 | TODO | Bộ công cụ Bash, health-check, cảnh báo | `tools/` |

## 4. Cách tái tạo hệ thống

TODO (hoàn thiện cuối cùng). Phần hạ tầng: xem `infra/README.md`.

## 5. Kiểm tra shellcheck toàn bộ script

```bash
shellcheck -x $(git ls-files '*.sh')
```
