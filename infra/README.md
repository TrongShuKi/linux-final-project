# infra/: Hạ tầng, mạng, SSH, firewall, auditd (TV1)

> **Trạng thái: DRAFT.** Script đã qua shellcheck và `-h`/dry-run, nhưng **chưa chạy trên VM/GCP thật**. Test từng cái trước khi tin, và sửa nếu gặp lỗi.

## Cấu trúc

```
infra/
├── lib/
│   ├── common.sh          log, die, trap ERR/EXIT, dry-run, require_root
│   └── gcp.sh             load env.sh, gcloud_exists
├── gcp/                   chạy ở Cloud Shell / máy có gcloud
│   ├── env.sh.example     copy thành env.sh rồi sửa PROJECT
│   ├── 01-network.sh      VPC, subnet, firewall VPC (22, 2222, 80, 443)
│   ├── 02-vms.sh          2 VM e2-small + ổ data
│   ├── 03-static-ip.sh    "nâng" IP hiện tại thành IP tĩnh
│   ├── snapshot.sh        snapshot 4 disk với một nhãn
│   └── 99-teardown.sh     XÓA tất cả (sau khi nộp bài)
├── vm/
│   ├── scripts/           chạy TRÊN VM bằng sudo
│   │   ├── bootstrap.sh       timezone, hosts, swap, lịch sử lệnh
│   │   ├── mount-data.sh      ổ data + fstab (UUID, nofail)
│   │   ├── add_user.sh        user + public key + nhóm labadmin
│   │   ├── ufw-setup.sh       UFW deny incoming, mở 22/2222 (+80/443)
│   │   ├── harden-ssh.sh      cài 99-hardening.conf có chống tự khóa
│   │   └── install-auditd.sh  auditd + luật passwd/shadow
│   └── etc/                   file cấu hình thật (phản chiếu đường dẫn /etc)
│       ├── ssh/sshd_config.d/99-hardening.conf
│       ├── audit/rules.d/lab.rules
│       ├── audit/optional/lab-rootcmds.rules
│       ├── sudoers.d/90-labadmin
│       └── profile.d/lab-history.sh
└── evidence/              ảnh chụp bằng chứng cho báo cáo (xem README trong đó)
```

## Thứ tự chạy

**Trong Cloud Shell** (đã `git clone` repo):

```bash
cd infra/gcp
cp env.sh.example env.sh && nano env.sh      # sửa PROJECT
./01-network.sh -n && ./01-network.sh        # -n là chạy thử
./02-vms.sh
./03-static-ip.sh
```

**Trên từng VM** (SSH vào, clone repo, `cd infra/vm/scripts`):

```bash
sudo ./bootstrap.sh -u                       # cả 2 VM
sudo ./mount-data.sh -m /srv/data            # lab-web  (VM2 dùng -m /srv/backup)
sudo ./add_user.sh -u trong -f ~/trong.pub   # lặp cho từng người, cả 2 VM
sudo ./ufw-setup.sh -w                       # lab-web (có -w); VM2 bỏ -w
sudo ./harden-ssh.sh -u "trong an dat bao tv5"   # SAU KHI mọi người đã vào được, giữ phiên cũ mở
sudo ./install-auditd.sh
```

Chụp snapshot trước `harden-ssh.sh`: `./snapshot.sh -l truoc-ssh` (chạy ở Cloud Shell).

## Lưu ý

- `AllowUsers` chỉ lọc theo tên user, không phụ thuộc IP.
- Cổng 2222 dùng chung cấu hình sshd với cổng 22. Chỉ cần mở ở VPC, UFW và thêm vào `port` của fail2ban (`port = 22,2222`, việc của TV2).
- Mọi script có `-h`, `set -Eeuo pipefail`, trap ERR/EXIT, log rõ ràng.
- Cổng 22 mở cho mọi IP vì IP team không cố định: bảo vệ bằng khóa + AllowUsers + fail2ban.
