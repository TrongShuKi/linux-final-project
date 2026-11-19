# Bằng chứng cho báo cáo (TV1)

Đề yêu cầu mọi khẳng định bảo mật/hạ tầng phải có ảnh chụp có chú thích hoặc file cấu hình thật. Chụp và đặt vào thư mục này, đặt tên theo mục:

| File ảnh | Chụp gì |
|---|---|
| `01-vm-list.png` | `gcloud compute instances list` (2 VM, IP, machine type) |
| `02-vpc-firewall.png` | `gcloud compute firewall-rules list --filter="network:lab-net"` |
| `03-hostname-fstab.png` | `hostnamectl`, `cat /etc/fstab`, `lsblk`, `df -h` sau reboot |
| `04-ufw-status.png` | `sudo ufw status verbose` (cả 2 VM) |
| `05-ssh-effective.png` | `sudo sshd -T \| grep -Ei 'port\|permitroot\|passwordauth\|allowusers'` |
| `06-ssh-root-denied.png` | thử đăng nhập root bị từ chối |
| `07-ssh-password-denied.png` | thử đăng nhập bằng mật khẩu bị từ chối |
| `08-allowusers-demo.png` | user mới bị từ chối → thêm vào AllowUsers → đăng nhập được |
| `09-auditd-shadow.png` | `sudo ausearch -k shadow_access -i` sau khi đọc `/etc/shadow` |
| `10-users-sudo.png` | danh sách user, nhóm `labadmin`, `sudo -l` |
| `11-shellcheck-clean.png` | `shellcheck -x` trên script của TV1, không còn lỗi |
