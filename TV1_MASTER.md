# TV1 MASTER — Đồ án Linux & Ứng dụng (GCP)

> **File sống.** Đây là nguồn context duy nhất cho vai TV1 (Hạ tầng & Mạng): bối cảnh, quyết định đã chốt, checklist, tiến độ, hướng dẫn SSH cho thành viên mới và quy ước làm việc của team.
> Thay thế `TV1_ke_hoach_va_ban_giao.md`. File `HUONG_DAN_TAO_SSH_KEY.md` vẫn dùng được, nhưng mục 7 dưới đây đã gộp đủ.
> **Cập nhật lần cuối:** 2026-11-20 · **Trạng thái:** đã xong P0–P3 (trừ P0.3, P1.5 chưa xác nhận), xong UFW (P6) và tài khoản TV1 trên cả 2 VM; đang chờ public key TV2–TV5 (P4)

---

## 0. Dành cho AI/người đọc tiếp theo (đọc trước)

**Cách dùng file này**
1. Đọc mục 1–3 để nắm bối cảnh và quyết định. **Không hỏi lại** những gì đã chốt ở mục 2.
2. Mục 5 là checklist + tiến độ. Việc tiếp theo là mục `[ ]` đầu tiên theo thứ tự ID (P0.1, P0.2, …).
3. Mục 6 là danh sách tiên quyết gửi team.

**Quy tắc cập nhật (bắt buộc sau mỗi bước)**
- Tick checklist: `[ ]` chưa làm · `[~]` đang làm · `[x]` xong. Ghi ngày + người làm vào cột bên cạnh.
- Điền kết quả thực tế vào mục 4 (bảng thông số). Không ghi mật khẩu, private key, token.
- Thêm một dòng vào mục 10 (nhật ký) cho mỗi thay đổi đáng kể trên GCP/VM.
- Quyết định mới → ghi mục 2. Việc còn treo → mục 11.
- Ưu tiên sửa theo kiểu diff nhỏ (str_replace), không viết lại cả file.

**Người dùng (TV1)**: Nguyễn Minh Trọng, sinh viên HCMUS, chuyên ngành MMT. Muốn giải thích rõ vì vấn đáp sẽ hỏi từng thiết lập; agent chỉ hỗ trợ, TV1 phải hiểu từng dòng. Giao tiếp tiếng Việt.

---

## 1. Bối cảnh đồ án

Môn **Hệ điều hành Linux & Ứng dụng** (HCMUS), giảng viên **thầy Minh**, lớp CQ2024/4. Nhóm 5 người. Xây **một hệ thống duy nhất** trên **≥ 2 VM**:

`trình duyệt/curl → Nginx (≥ 2 vhost, HTTPS tự ký) → app systemd (Flask/FastAPI/Node) → DB (PostgreSQL/MySQL, chỉ nghe localhost)`; VM thứ 2 nhận backup bằng rsync. Vận hành qua bộ script Bash có menu (deploy có rollback, backup/restore, health-check + cảnh báo, log rotate), toàn bộ qua shellcheck.

Chấm điểm: Hệ thống chạy được 30% · Bảo mật 20% · Sao lưu & khôi phục 20% · Tự động hóa 15% · Báo cáo & vấn đáp 15%. Demo 12–15 phút trên VM của nhóm, vấn đáp hỏi bất kỳ thành viên nào về bất kỳ phần nào.

**Phân công**

| TV | Người | Phần |
|---|---|---|
| TV1 | Trọng | Hạ tầng, mạng, SSH, firewall, auditd |
| TV2 | An | Nginx reverse proxy, vhost, TLS tự ký, fail2ban |
| TV3 | Đạt | App + systemd |
| TV4 | Bảo | CSDL + backup/restore + lịch chạy |
| TV5 | (chưa ghi tên) | Bộ công cụ Bash, health-check, cảnh báo, shellcheck |
| Chung | cả nhóm | Lynis + khắc phục 3 mục, README, demo, vấn đáp |

**Phạm vi TV1 theo đề:** Mục 1, 2.1, 2.2 (firewall, SSH, auditd), 3.2 (kiến trúc 2 VM, sơ đồ), 11 (checklist). Báo cáo: "Tổng quan hệ thống" + "Bảo mật (firewall/SSH)".

**Mốc thời gian:** sheet của nhóm ghi TV1 xong hạ tầng cơ bản **cuối ngày 14/11** (đã qua). Hiện là 19/11 nên ưu tiên tối đa để team không bị chặn.

**Hạn nộp: 3/12/2026, 22:00** (còn khoảng 14 ngày). Ngày demo chưa rõ (mục 11).

Lộ trình đề xuất (chờ team đồng ý):

| Mốc | Việc |
|---|---|
| 18–19/11 | TV1 xong P0–P4, cả team SSH vào được |
| 20–22/11 | TV1 làm UFW/SSH hardening/auditd; TV2–TV5 dựng phần của mình song song |
| 23–26/11 | Ráp hệ thống đầu–cuối (Nginx → app → DB, backup/restore, health-check) |
| 27–29/11 | Lynis + khắc phục, báo cáo, tập demo, chụp snapshot sạch |
| 30/11–2/12 | Đệm: sửa lỗi, đóng gói tar.gz, kiểm tra shellcheck, README |
| **3/12 trước 22:00** | **Nộp**, nên nộp sớm vài giờ để tránh sự cố |

---

## 2. Quyết định đã chốt

| # | Quyết định | Ghi chú |
|---|---|---|
| D1 | Thầy Minh **đã xác nhận được dùng toàn bộ trên cloud (GCP)** | Thay VirtualBox/VMware. Báo cáo phải ghi rõ việc dùng GCP, lý do, khác biệt mạng (VPC firewall + UFW) |
| D2 | **Ubuntu 22.04 LTS Server**, 2 VM | `lab-web` (chính), `lab-bkp` (nhận backup) |
| D3 | Cấu hình: **e2-small × 2** (2 vCPU chia sẻ, 2 GB RAM), boot 10 GB + ổ data 10 GB, `pd-standard` | Xem mục 3. Không có phương án free khớp cấu hình này |
| D4 | Region **asia-southeast1 (Singapore)** | Gần VN nhất |
| D5 | **VPC custom** `lab-net`, subnet `10.10.0.0/24`; IP nội bộ cố định `10.10.0.10` / `10.10.0.20` | Rule do mình tự viết nên giải thích được từng dòng khi vấn đáp |
| D6 | SSH: **tắt root, chỉ dùng khóa, tắt password, `AllowUsers`, hai cổng SSH 22 và 2222**; fail2ban (TV2) bảo vệ cả hai cổng. VPC mở 22 và 2222 cho `0.0.0.0/0` | IP nhà các thành viên không cố định. Đánh đổi ghi vào báo cáo: cổng 22 lộ ra Internet, nhiều lượt dò từ bot. Cổng 2222 là cổng **dự phòng** (cổng 22 dùng hằng ngày), chống tự khóa do lỗi firewall/cổng; sai `AllowUsers` vẫn khóa cả hai cổng nên vẫn cần snapshot + startup-script ở 9.9; chỉ khi đóng 22 ở cuối mới tính là "đổi cổng" (quyết định ở P9, mục 11). `AllowUsers` vẫn là phương án chính đáp ứng yêu cầu của đề |
| D7 | TLS: **chứng chỉ tự ký** bằng openssl, **không dùng domain thật**; vhost là tên giả `app.lab.local`, `status.lab.local` | Truy cập bằng `curl -H "Host: ..."` hoặc file hosts |
| D8 | **(Đã chốt)** Mỗi thành viên có **user riêng + khóa riêng**, thêm bằng script `add_user.sh` (mục 9.4; bản chuẩn ở `infra/vm/scripts/add_user.sh` trong repo) | Tài khoản tạo thủ công, không dùng OS Login. **Không dùng chung một user.** Lý do: auditd/log ghi đúng người thao tác, gỡ quyền từng người được, không phải chia sẻ private key, `AllowUsers` có ý nghĩa, và vấn đáp hỏi được "ai đã làm gì". File dùng chung thì cho vào thư mục của nhóm `labadmin` (xem 8.1, quy tắc 12) |
| D9 | Mọi cấu hình/script nằm trong **repo Git** (nguồn sự thật), để dựng lại được trên VMware nếu cần | Repo chưa tạo (mục 11) |
| D10 | **IP tĩnh cho cả 2 VM** | "Nâng" IP đang dùng thành IP tĩnh ngay sau khi tạo VM (lệnh 9.1). Xóa sau khi nộp bài để khỏi bị tính phí |
| D11 | **Quyền quản trị** (đề xuất, chờ Trọng chốt): GCP Owner là TV1; trong VM `root` khóa đăng nhập, 5 user trong `labadmin` đều có sudo | Chi tiết ở 8.6 |
| D12 | **(Đã chốt)** Demo `AllowUsers`: tạo user mới → thử đăng nhập bị từ chối → thêm vào `AllowUsers` → đăng nhập lại được | Kịch bản chi tiết ở 8.7 |

---

## 3. Cấu hình VM và chi phí

### 3.1 Vì sao e2-small (không dùng free tier được)

- **Always Free** của GCP chỉ gồm **1 VM e2-micro** (2 vCPU chia sẻ, **1 GB RAM**), chỉ miễn phí ở `us-west1`, `us-central1`, `us-east1`, kèm 30 GB disk standard. Không khớp yêu cầu 2 GB RAM, chỉ có một VM, và ở Mỹ (độ trễ cao khi SSH/demo).
- **e2-small** (2 vCPU chia sẻ, 2 GB RAM) là cấu hình rẻ nhất khớp đúng "2 core, 2 GB". Giá tham khảo khoảng **$12–13/tháng/VM** ở Mỹ, Singapore thường nhỉnh hơn chút. **Kiểm tra lại bằng Google Cloud Pricing Calculator** trước khi tin con số.
- Lưu ý: e2-small là **shared-core** (CPU baseline thấp, burst được). Khi chạy health-check/Lynis/stress để demo ngưỡng CPU có thể thấy số liệu khác máy thật. Nên biết để giải thích.

### 3.2 Thông số đã chốt

| | `lab-web` | `lab-bkp` |
|---|---|---|
| Vai trò | Nginx + App + DB (localhost) | Nhận backup (rsync) |
| Machine | e2-small | e2-small |
| Zone | `asia-southeast1-b` | `asia-southeast1-b` |
| Image | ubuntu-2204-lts | ubuntu-2204-lts |
| Boot disk | 10 GB `pd-standard` | 10 GB `pd-standard` |
| Ổ data | 10 GB `pd-standard` → `/srv/data` | 10 GB `pd-standard` → `/srv/backup` |
| IP nội bộ | `10.10.0.10` | `10.10.0.20` |
| Tag | `web` | (không) |

Ổ data 10 GB là mức nhỏ nhất thường cho phép cho persistent disk. Nếu gcloud báo lỗi kích thước thì chỉnh theo thông báo. Disk có thể mở rộng sau nên không cần dư từ đầu.

### 3.3 Ước tính chi phí (cần kiểm chứng)

- 2 × e2-small chạy 24/7: khoảng $25–30/tháng. Disk `pd-standard` 40 GB: khoảng $1–2/tháng.
- Theo mình biết, IPv4 external cũng bị tính phí nhỏ theo giờ. Kiểm tra trên bảng giá/billing.
- Credit còn khoảng **$90** → chạy liên tục được chừng 3 tháng, **tắt VM khi không làm thì kéo dài nhiều hơn**. Tài khoản trial hết hạn 7/2/2027 nên giới hạn thật là credit. Hạn nộp 3/12 (còn ~14 ngày) nên chạy gần như liên tục cũng chỉ khoảng $13–15 cho 2 VM; vẫn nên tắt khi không ai làm. **Sau khi nộp và chấm xong, xóa VM, disk, snapshot và IP tĩnh** để khỏi bị tính phí.
- **Phương án tiết kiệm (không chọn mặc định):** đặt `lab-bkp` là e2-micro ở `us-central1` (miễn phí). Đổi lại chỉ 1 GB RAM, nằm khác region, và độ trễ cao. Chỉ cân nhắc nếu credit cạn.

---

## 4. Bảng thông số thực tế (điền khi làm xong)

> Không ghi mật khẩu/private key vào đây.

| Mục | Giá trị |
|---|---|
| GCP project ID | `manger-vms` |
| IP public `lab-web` | `34.126.146.150` |
| IP public `lab-bkp` | `34.87.119.173` |
| IP tĩnh đã reserve? | Rồi (`lab-web-ip`, `lab-bkp-ip`) |
| Host key fingerprint `lab-web` (ed25519) | `256 SHA256:5HyRHZJL1S5+ghHL8DQLT7EQXkTp92VS6ygBNcq4to4 root@lab-web (ED25519)` |
| Host key fingerprint `lab-bkp` (ed25519) | `256 SHA256:UxCblO2o4HU+sSia38pbu0bI3GaA1W5cEvW2ZjzzPO0 root@lab-bkp (ED25519)` |
| Repo Git | Đã tạo GitHub repo và push skeleton _(chưa ghi URL)_ |

**Tài khoản**

| TV | Username | Public key đã nạp | Vào được VM1 | Vào được VM2 |
|---|---|---|---|---|
| TV1 Trọng | `trong` | ✓ cả 2 VM | ✓ | ✓ |
| TV2 An | | | | |
| TV3 Đạt | | | | |
| TV4 Bảo | | | | |
| TV5 | | | | |

**VPC firewall**

| Rule | Cổng | Nguồn | Áp dụng | Lý do |
|---|---|---|---|---|
| `lab-allow-internal` | tcp, udp, icmp | `10.10.0.0/24` | cả 2 VM | rsync backup, kết nối nội bộ |
| `lab-allow-ssh` | tcp:22, tcp:2222 | `0.0.0.0/0` | cả 2 VM | quản trị (IP team không cố định; chặn bằng khóa + AllowUsers + fail2ban) |
| `lab-allow-web` | tcp:80, 443 | `0.0.0.0/0` | tag `web` | HTTP→HTTPS, HTTPS |

**UFW (trong VM)**: default deny incoming / allow outgoing

| VM | Cổng | Lý do | Rủi ro nếu bị khai thác |
|---|---|---|---|
| cả 2 | 22/tcp | SSH quản trị (cổng dùng hằng ngày, cũng là cổng của SSH trình duyệt GCP) | brute-force, lộ khóa |
| cả 2 | 2222/tcp | SSH quản trị (cổng dự phòng) | brute-force, lộ khóa |
| `lab-web` | 80/tcp | HTTP, redirect sang 443 | |
| `lab-web` | 443/tcp | HTTPS | |
| `lab-web` | cổng app, cổng DB | **không mở**, chỉ nghe `127.0.0.1` | |

**Bằng chứng cho báo cáo** (ảnh chụp/đường dẫn file):
- `evidence-TV1/01-vm-list.png`
- `evidence-TV1/02-vpc-firewall.png`
- `evidence-TV1/03-hostname-fstab-lab-web.png`
- `evidence-TV1/03-hostname-fstab-lab-bkp.png`
- `evidence-TV1/04-ufw-status-lab-web.png`, `evidence-TV1/04-ufw-status-lab-bkp.png`
- `evidence-TV1/mount data.png`, `evidence-TV1/mount data - bkp vm.png`

---

## 5. CHECKLIST TV1 — từ dựng cloud đến 2 VM hoàn chỉnh

Legend: `[ ]` chưa · `[~]` đang làm · `[x]` xong. ★ = **tiên quyết** (team đang chờ).

### P0 — Chuẩn bị GCP ★
- [x] P0.1 Tạo project GCP (`manger-vms`), gắn billing/trial *(2026-11-20, Trọng)*
- [x] P0.2 Bật Compute Engine API *(2026-11-20, Trọng)*
- [ ] P0.3 **Budget alert** (vd. $30 / $60 / $80) gửi email *(chưa xác nhận)*
- [x] P0.4 Chọn công cụ chạy lệnh: **Cloud Shell** (trên trình duyệt, có sẵn gcloud) *(2026-11-20, Trọng)*
- [x] P0.5 Tạo khóa SSH của TV1 (`ssh-keygen -t ed25519`) *(2026-11-20, Trọng)*

### P1 — Mạng ★
- [x] P1.1 Tạo VPC custom `lab-net` + subnet `lab-subnet` (`10.10.0.0/24`, `asia-southeast1`) *(2026-11-20, Trọng)*
- [x] P1.2 Firewall `lab-allow-internal` *(2026-11-20, Trọng)*
- [x] P1.3 Firewall `lab-allow-ssh` (22 và 2222, `0.0.0.0/0`, theo D6) *(2026-11-20, Trọng)*
- [x] P1.4 Firewall `lab-allow-web` (80/443, tag `web`) *(2026-11-20, Trọng)*
- [ ] P1.5 Xóa/siết rule thừa của mạng `default` (rule SSH/RDP mở rộng), vì không dùng mạng đó

### P2 — Dựng 2 VM ★
- [x] P2.1 Tạo `lab-web` (e2-small, 10 GB boot + 10 GB data, `10.10.0.10`, tag `web`) *(2026-11-20, Trọng)*
- [x] P2.2 Tạo `lab-bkp` (e2-small, 10 GB boot + 10 GB data, `10.10.0.20`) *(2026-11-20, Trọng)*
- [x] P2.3 SSH vào được cả hai (`gcloud compute ssh` hoặc SSH trên trình duyệt) để xác nhận *(2026-11-20, Trọng)*
- [x] P2.4 **Reserve IP tĩnh cho cả 2 VM** (D10) bằng cách "nâng" IP hiện tại (lệnh 9.1), ghi IP vào mục 4 *(2026-11-20, Trọng)*

### P3 — OS cơ bản (làm trên cả 2 VM)
- [x] P3.1 Xác nhận hostname (`hostnamectl`): `lab-web` và `lab-bkp`, còn nguyên sau reboot *(2026-11-20, Trọng)*
- [x] P3.2 `timedatectl set-timezone Asia/Ho_Chi_Minh` *(2026-11-20, Trọng)*
- [x] P3.3 `apt update && apt upgrade` *(2026-11-20, Trọng)*
- [x] P3.4 `/etc/hosts`: `10.10.0.10 lab-web`, `10.10.0.20 lab-bkp` *(2026-11-20, Trọng)*
- [x] P3.5 Swap 1 GB (RAM chỉ 2 GB, mục 9.2) *(2026-11-20, Trọng)*
- [x] P3.6 Ổ data: `mkfs.ext4` → mount `/srv/data` (`lab-web`) và `/srv/backup` (`lab-bkp`) bằng **UUID** trong `/etc/fstab` với `nofail`, đã reboot kiểm tra *(2026-11-20, Trọng)*

### P4 — Tài khoản cho team ★ (team bắt đầu làm được từ bước này)
- [x] P4.1 Tạo nhóm `labadmin` + sudoers NOPASSWD cho nhóm này *(2026-11-20, Trọng)*
- [x] P4.2 Tạo user + nạp public key cho TV1 (`trong` trên cả 2 VM) *(2026-11-20, Trọng)*
- [ ] P4.3 Thu public key + username của TV2–TV5 (gửi hướng dẫn mục 6/7)
- [ ] P4.4 Chạy `add_user.sh` cho từng người trên **cả 2 VM**
- [ ] P4.5 Từng người xác nhận SSH vào được (điền bảng mục 4)
- [~] P4.6 Công bố host key fingerprint cho team để đối chiếu lần kết nối đầu *(đã lấy fingerprint cả 2 VM, chờ gửi team)*
- [x] P4.7 Cài `/etc/profile.d/lab-history.sh` để lưu lịch sử lệnh từng người *(2026-11-20, Trọng)*

### P5 — Kết nối nội bộ VM1 ↔ VM2 (phục vụ rsync backup của TV4)
- [ ] P5.1 Ping/SSH qua IP nội bộ giữa 2 VM
- [ ] P5.2 Tạo user chuyên dụng cho backup trên `lab-bkp` (vd. `backup`), nạp khóa của VM1 → VM2 (không dùng khóa cá nhân)
- [ ] P5.3 Test `rsync` 1 file nhỏ qua key đó
- [ ] P5.4 (Tùy chọn) Cấu hình SSH `ProxyJump` nếu coi một VM là bastion

### P6 — UFW
- [x] P6.1 `ufw default deny incoming` / `allow outgoing` *(2026-11-20, Trọng)*
- [x] P6.2 `ufw allow 22/tcp` và `ufw allow 2222/tcp` **trước** `ufw enable` *(2026-11-20, Trọng)*
- [x] P6.3 `ufw enable`, `ufw status verbose`, chụp ảnh *(2026-11-20, Trọng)*
- [x] P6.4 Mở sẵn 80/443 trên `lab-web` (`ufw-setup.sh -w`) *(2026-11-20, Trọng — chạy lại `sudo ufw status verbose` trên `lab-web` để kiểm tra đủ rule IPv4 80/443)*
- [ ] P6.5 Hoàn thành bảng lý do từng cổng (mục 4)

### P7 — Gia cố SSH (**snapshot disk trước khi làm**)
- [ ] P7.1 Snapshot disk cả 2 VM
- [ ] P7.2 Kiểm tra cấu hình hiện tại (`sudo sshd -T`)
- [ ] P7.3 Viết `/etc/ssh/sshd_config.d/99-hardening.conf`: `Port 22`, `Port 2222`, `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `AllowUsers <5 user>`, `MaxAuthTries 3`, `LoginGraceTime 30`
- [ ] P7.4 `sshd -t` → reload, **giữ phiên SSH cũ mở**, mở phiên mới để test trước khi đóng
- [ ] P7.5 Chứng minh: root login bị từ chối, password bị từ chối (chụp ảnh)
- [ ] P7.6 Ghi giải thích từng dòng "ngăn kiểu tấn công nào" + đánh đổi của D6 vào báo cáo
- [ ] P7.7 Báo TV2 cả hai cổng SSH (22 và 2222) để cấu hình fail2ban (`port = 22,2222`); nhắc `ignoreip` cho IP team

### P8 — auditd
- [ ] P8.1 Cài `auditd audispd-plugins`
- [ ] P8.2 Luật theo dõi `/etc/passwd`, `/etc/shadow` trong `/etc/audit/rules.d/lab.rules`
- [ ] P8.3 `augenrules --load`, bật dịch vụ
- [ ] P8.4 Test đọc `/etc/shadow`, `ausearch -k shadow_access -i`, chụp ảnh
- [ ] P8.5 (Tùy chọn) Luật auditd ghi lệnh chạy bằng quyền root theo từng người (mục 9.10)

### P9 — Hoàn thiện và bàn giao
- [ ] P9.1 Reboot cả 2 VM: mount, UFW, SSH, auditd còn nguyên
- [ ] P9.2 Snapshot "sạch" cả 2 VM (`lab-web-clean`, `lab-bkp-clean`), ghi lệnh khôi phục chính xác
- [ ] P9.3 Điền đầy đủ mục 4, gửi team báo "hạ tầng xong"
- [ ] P9.4 Xuất file cấu hình thật vào repo: `sshd_config` (hoặc file `.d`), `lab.rules`, UFW rules, `fstab`
- [ ] P9.5 Sơ đồ kiến trúc 2 VM cho báo cáo
- [ ] P9.6 Hoàn thiện repo `infra/` (skeleton đã có, mục 12): test từng script trên VM/GCP thật, sửa lỗi, chạy shellcheck, push lên Git

### P10 — Chung cả nhóm
- [ ] P10.1 Lynis chạy trên VM chính, ghi điểm, khắc phục ≥ 3 mục
- [ ] P10.2 Phần báo cáo TV1: Tổng quan hệ thống + Bảo mật (firewall/SSH/auditd)
- [ ] P10.3 README.md, đóng gói `MSSV1_MSSV2_….tar.gz`
- [ ] P10.4 Tập demo (snapshot trước demo, hotspot dự phòng)
- [ ] P10.5 Tự trả lời được các câu vấn đáp ở mục 8.4

---

## 6. TIÊN QUYẾT — gửi team ngay

> Copy khối dưới vào group. Khi TV1 xong P0–P4, cập nhật IP và username rồi gửi tiếp.

```
[TV1 → cả nhóm] Hạ tầng GCP đang dựng. Mỗi người làm 3 việc này TRƯỚC:

1. Tạo SSH key (nếu chưa có key ed25519) rồi gửi cho mình:
   - 1 dòng public key (bắt đầu bằng ssh-ed25519 AAAA...)
   - username muốn dùng trên VM (chữ thường, không dấu, vd: an, dat, bao)
   Hướng dẫn tạo key: mục 7.1 trong TV1_MASTER.md
   !! CHỈ gửi file .pub. TUYỆT ĐỐI không gửi private key (file không có đuôi .pub).

2. Đọc mục 8 (quy ước làm việc trên cloud) trong TV1_MASTER.md, góp ý trước khi chốt.

3. Chưa cài/sửa gì trên VM khi mình chưa báo "VM xong". Lúc đó mình gửi IP + lệnh SSH.

Những thứ cần team chốt sớm (mục 8.2): repo Git, cổng app, DB dùng PostgreSQL hay MySQL,
tên 2 vhost, kênh cảnh báo (msmtp hay Telegram).
```

**Việc TV1 phải xong trước để team không bị chặn:** P0 → P1.1–P1.3 → P2 → P3 → P4. Gia cố SSH (P7) làm ngay sau khi mọi người vào được, không để VM chạy lâu ở trạng thái mặc định vì cổng 22 mở ra Internet.

---

## 7. Hướng dẫn SSH vào cloud (cho thành viên mới)

### 7.1 Tạo khóa

Mở **PowerShell** (Windows) hoặc **Terminal** (Mac/Linux). Nếu Windows báo không có `ssh-keygen`: *Settings → Apps → Optional features → Add a feature → OpenSSH Client*.

```bash
# Kiểm tra đã có key chưa (có thì dùng lại, bỏ qua bước tạo)
ls ~/.ssh/id_ed25519.pub                                   # Mac/Linux
Test-Path $env:USERPROFILE\.ssh\id_ed25519.pub              # Windows PowerShell

# Tạo mới (thay ten-cua-ban bằng username)
ssh-keygen -t ed25519 -C "ten-cua-ban"
```

Enter để dùng đường dẫn mặc định, nên đặt passphrase. Nếu nó hỏi có ghi đè không, chọn **N**.

In public key để gửi cho TV1:

```bash
cat ~/.ssh/id_ed25519.pub                                   # Mac/Linux
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub            # Windows PowerShell
```

| File | Là gì | Được gửi? |
|---|---|---|
| `id_ed25519` | **Private key** | ❌ Tuyệt đối không |
| `id_ed25519.pub` | Public key | ✅ Gửi cho TV1 |

Gửi nhầm private key (nội dung bắt đầu `-----BEGIN OPENSSH PRIVATE KEY-----`): báo ngay, tạo lại key mới, bỏ key cũ.

### 7.2 Kết nối

Sau khi TV1 báo xong và gửi IP + username:

```bash
# Cổng 22 dùng hằng ngày; cổng 2222 là dự phòng (thêm -p 2222 nếu cổng 22 có vấn đề)
ssh <username>@<IP_PUBLIC_lab-web>
ssh <username>@<IP_PUBLIC_lab-bkp>
```

Lần đầu máy hỏi xác nhận fingerprint. **Đối chiếu với fingerprint TV1 đã công bố** (mục 4) rồi mới gõ `yes`.

Cấu hình tắt cho gọn, thêm vào `~/.ssh/config` (Windows: `C:\Users\<bạn>\.ssh\config`):

```
Host lab-web
    HostName <IP_PUBLIC_lab-web>
    User <username>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30

Host lab-bkp
    HostName <IP_PUBLIC_lab-bkp>
    User <username>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
```

Rồi chỉ cần `ssh lab-web` / `ssh lab-bkp`.

### 7.3 Truy cập web để thử

Thêm vào file hosts trên máy bạn (Windows: `C:\Windows\System32\drivers\etc\hosts`, cần quyền admin; Mac/Linux: `/etc/hosts`):

```
<IP_PUBLIC_lab-web> app.lab.local status.lab.local
```

Hoặc dùng curl, không cần sửa gì:

```bash
curl -k -H "Host: app.lab.local" https://<IP_PUBLIC_lab-web>/
```

Trình duyệt sẽ cảnh báo chứng chỉ không tin cậy (do tự ký), bình thường. **IP public có thể đổi** nếu VM tắt/bật mà chưa reserve IP tĩnh. Khi TV1 báo đổi IP thì sửa lại hosts và `~/.ssh/config`.

### 7.4 Lỗi thường gặp

| Lỗi | Nguyên nhân thường gặp |
|---|---|
| `Permission denied (publickey)` | Sai username, key chưa được nạp, dùng nhầm file key, hoặc user không nằm trong `AllowUsers` |
| `Connection timed out` | Sai IP, VM đang tắt, hoặc firewall (VPC/UFW) chưa mở. Báo TV1 |
| `UNPROTECTED PRIVATE KEY FILE` (Mac/Linux) | `chmod 600 ~/.ssh/id_ed25519` |
| Đang gõ thì bị chặn | fail2ban ban IP của bạn (gõ sai nhiều lần). Báo TV1/TV2 để gỡ ban |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM bị dựng lại hoặc IP gán sang máy khác. Hỏi TV1 trước, đừng tự xóa `known_hosts` |

---

## 8. Quy ước làm việc trên cloud (cần team thống nhất)

### 8.1 Quy tắc chung (đề xuất, chờ team đồng ý)

1. **Mọi cấu hình quan trọng phải có trong repo Git.** Sửa trên VM xong thì copy/commit lại. Nếu VM hỏng hoặc phải về VMware, repo là thứ dựng lại được hệ thống, và đề cũng bắt nộp file cấu hình thật.
2. **Mỗi người sửa phần của mình.** TV1 giữ `sshd_config`, UFW, VPC firewall, auditd, fstab. TV2 giữ Nginx/TLS/fail2ban. TV3 giữ app/systemd. TV4 giữ DB/backup. TV5 giữ script/menu. Muốn đụng vào phần người khác thì nhắn trước.
3. **Backup trước khi sửa:** `sudo cp file file.bak.$(date +%F)`.
4. **Không làm bằng root**, dùng tài khoản cá nhân + `sudo`. Không `chmod 777`.
5. **Không tự `shutdown/reboot/stop` VM** khi chưa báo trong group (người khác có thể đang làm dở; stop/start còn làm đổi IP public nếu chưa reserve IP tĩnh).
6. **Bí mật (mật khẩu DB, token…) không đưa vào repo, chat, file md này.** Để trong `EnvironmentFile` quyền hạn chế (TV3/TV4).
7. **Không đặt dữ liệu thật** trong CSDL demo, vì web đang public ra Internet.
8. **Chỉ Nginx nhận 80/443 từ ngoài.** App và DB chỉ nghe `127.0.0.1`. Không mở cổng app/DB ở VPC hay UFW.
9. **RAM chỉ 2 GB, 5 người dùng chung.** **Không dùng VS Code Remote-SSH/agent remote server trên VM** (mỗi phiên ngốn vài trăm MB, dễ OOM). Sửa file bằng `nano`/`vim` hoặc sửa ở máy rồi `scp`/git. Trước khi chạy việc nặng (cài gói lớn, Lynis, build), chạy `free -h` và `w`.
10. **Ghi lại thay đổi trên VM** vào bảng nhật ký (mục 10) hoặc commit message rõ ràng.
11. **Credit có hạn.** TV1 là người tắt/bật VM theo lịch; mọi người báo nếu cần VM chạy qua đêm.
12. **(Tùy chọn) Thư mục dùng chung thuộc nhóm `labadmin`, có setgid**, chỉ cần nếu nhiều người cùng sửa file trong đó mà không dùng `sudo`. Quy trình chính: mỗi người clone repo về home của mình, push lên Git, và script deploy dùng `sudo` đưa file vào chỗ (`/etc/nginx`, `/opt/app`...). Làm vậy thì không cần cấu hình nhóm. Nếu vẫn muốn thư mục chung:
    ```bash
    sudo install -d -m 2775 -o root -g labadmin /opt/app /opt/labtools
    ```
    Mỗi người dùng `umask 002` khi làm trong các thư mục này (hoặc `chmod g+w` sau khi tạo file).
13. **Mọi thay đổi phục vụ đồ án phải nằm ở cấp hệ thống** (`/etc/...`, `/opt/...`, `/srv/...`, `/var/www/...`) **và có trong repo**. Nếu một thay đổi chỉ tồn tại riêng trong user của bạn mà hệ thống cần nó để chạy, **phải báo lại trong group** để đưa lên cấp hệ thống, vì lúc demo/vấn đáp có thể người khác là người thao tác. Ví dụ hay gặp:

    | Làm riêng trong user (dễ sót) | Nên làm ở cấp hệ thống |
    |---|---|
    | `crontab -e` của user | `/etc/cron.d/<tên>` hoặc systemd timer |
    | `pip install --user`, `npm -g` vào home | venv trong `/opt/app` |
    | Biến môi trường trong `~/.bashrc` hoặc `~/.env` | `EnvironmentFile` quyền hạn chế trong `/etc/...` |
    | Script để trong `~/` | `/opt/labtools` và có trong repo |
    | Alias, cấu hình `~/.ssh/config` của máy bạn | Không phải việc của hệ thống, chỉ cần với bạn thì khỏi báo |

### 8.2 Cần team chốt (điền khi có kết quả)

| Mục | Đề xuất | Chốt |
|---|---|---|
| Repo Git | GitHub private, thư mục `infra/`, `proxy/`, `app/`, `db-backup/`, `tools/` | _(chưa)_ |
| Cổng app | `127.0.0.1:8000` | _(chưa)_ |
| DB | PostgreSQL, `127.0.0.1:5432` | _(chưa)_ |
| Stack app | Flask hoặc FastAPI | _(TV3 chọn)_ |
| 2 vhost | `app.lab.local`, `status.lab.local` | _(chưa)_ |
| Kênh cảnh báo | msmtp qua cổng 587 (hoặc Telegram). **GCP chặn cổng 25 outbound**, nên `mail` gửi thẳng không đi được | _(TV5 chọn)_ |
| Thư mục chuẩn | App: `/opt/app` · Site tĩnh: `/var/www/<vhost>` · Script: `/opt/labtools` · Dữ liệu: `/srv/data` · Backup VM2: `/srv/backup` | _(chưa)_ |
| Timezone | Asia/Ho_Chi_Minh | ✓ |

### 8.3 Cách làm chung mà ít đạp chân nhau

- Trước khi làm nặng: `w` (xem ai đang đăng nhập), nhắn group "mình đang sửa Nginx".
- Dùng `tmux` nếu muốn giữ phiên khi rớt mạng.
- Cấu hình nhạy cảm (SSH, UFW, firewall): **một người sửa, người khác không sửa song song**.

### 8.4 Câu hỏi vấn đáp TV1 cần tự trả lời được

- Vì sao mở đúng những cổng đó? Kẻ tấn công được lợi gì từ mỗi cổng?
- Từng dòng `sshd_config` ngăn kiểu tấn công nào? `AllowUsers` khác đổi cổng thế nào? Vì sao cổng 22 mở cho mọi IP vẫn chấp nhận được?
- UFW và VPC firewall khác nhau ra sao? Nếu một lớp cấu hình sai thì sao?
- Vì sao `fstab` dùng UUID? `nofail` để làm gì?
- `-p rwa` trong luật auditd nghĩa là gì? Log ghi những gì khi đọc `/etc/shadow`?
- Vì sao NOPASSWD cho nhóm `labadmin` là đánh đổi? Vì sao vẫn chọn?
- Vì sao dùng chứng chỉ tự ký, không dùng Let's Encrypt?

### 8.5 Demo: dùng user nào

- Mỗi lần demo có **một người cầm lái**, dùng user của mình và chia sẻ màn hình. Kết quả không phụ thuộc user vì mọi thứ demo (Nginx, app, DB, backup, UFW, fail2ban, auditd) đều là cấp hệ thống.
- Với user riêng, auditd còn cho thấy ai đã truy cập `/etc/shadow` (`auid=<tên>` trong `ausearch -i`), là điểm cộng khi trình bày.
- **Mọi thành viên phải SSH được bằng user của mình**, vì giảng viên có thể gọi bất kỳ ai thao tác lại. Cả nhóm thử đăng nhập một lần trước ngày demo.
- Vì demo có thể do người khác chạy, quy tắc 13 ở 8.1 là bắt buộc: không để thứ gì chỉ chạy được bằng user của một người.
- Chuẩn bị: mở sẵn 2 phiên SSH (VM1, VM2), có `tmux`, hotspot dự phòng, snapshot sạch.

### 8.6 Ai là quản trị cấp cao nhất

Có hai tầng tách bạch (đề xuất D11):

| Tầng | Ai | Quyền |
|---|---|---|
| GCP project (Console/gcloud) | **TV1 là Owner**; có thể thêm 1 người dự phòng (vai trò Compute Instance Admin) phòng ngày demo TV1 mất liên lạc | Tạo/xóa/reset VM, sửa firewall VPC, snapshot, xem Cloud Audit Logs. Ai sửa được metadata của VM thì chèn được SSH key/startup-script, tức có thể thành root, nên giữ danh sách này hẹp |
| Hệ điều hành trong VM | `root` bị khóa đăng nhập. 5 user trong nhóm `labadmin` đều có sudo ngang nhau | Mọi lệnh quản trị đi qua `sudo` nên gắn được với tên người chạy (xem 9.10) |

Về kỹ thuật cả 5 người đều là admin trong VM. "Người giữ" từng phần chỉ là quy ước (quy tắc 2): TV1 giữ sshd/UFW/VPC/auditd. Nếu muốn chặt hơn (đặc quyền tối thiểu) có thể giới hạn sudo theo phần việc từng người trong `/etc/sudoers.d/`, nhưng tốn công và dễ làm kẹt nhau khi sát hạn nộp, nên chưa làm.

### 8.7 Kịch bản demo `AllowUsers` (D12)

Người demo làm trên `lab-web`, giữ một phiên admin mở suốt:

1. **Tạo user mới** và nạp khóa (dùng luôn public key của người demo):
   ```bash
   sudo ./add_user.sh -u demo1 -f ~/.ssh/id_ed25519.pub
   ```
   Script sẽ cảnh báo "AllowUsers đang bật và chưa có demo1".
2. **Thử đăng nhập từ terminal thứ hai** (ssh dùng khóa mặc định):
   ```bash
   ssh demo1@<IP_PUBLIC_lab-web>        # → Permission denied (publickey)
   ```
   Cho giảng viên xem lý do trong log:
   ```bash
   sudo grep "not allowed because not listed in AllowUsers" /var/log/auth.log | tail -2
   ```
3. **Thêm `demo1` vào `AllowUsers`** trong `/etc/ssh/sshd_config.d/99-hardening.conf`, rồi kiểm tra và reload:
   ```bash
   sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
   sudo sshd -t && sudo systemctl reload ssh
   sudo sshd -T | grep -i allowusers
   ```
4. **Thử lại** `ssh demo1@<IP_PUBLIC_lab-web>` → vào được.
5. **Dọn dẹp:** `sudo deluser --remove-home demo1`, rồi bỏ `demo1` khỏi `AllowUsers` và reload lần nữa.

Lưu ý: chỉ thử sai **một lần** (fail2ban có thể ban nếu gõ sai nhiều lần). Tập trước ít nhất một lần, và chụp ảnh các bước làm bằng chứng (`08-allowusers-demo.png`).

---

## 9. Phụ lục: lệnh và file mẫu

### 9.1 Dựng mạng và VM (chạy trong Cloud Shell hoặc máy có gcloud)

```bash
PROJECT=<project-id>
REGION=asia-southeast1
ZONE=asia-southeast1-b
gcloud config set project "$PROJECT"

# Mạng
gcloud compute networks create lab-net --subnet-mode=custom
gcloud compute networks subnets create lab-subnet \
  --network=lab-net --range=10.10.0.0/24 --region="$REGION"

# Firewall VPC
gcloud compute firewall-rules create lab-allow-internal \
  --network=lab-net --allow=tcp,udp,icmp --source-ranges=10.10.0.0/24
gcloud compute firewall-rules create lab-allow-ssh \
  --network=lab-net --allow=tcp:22,tcp:2222 --source-ranges=0.0.0.0/0
gcloud compute firewall-rules create lab-allow-web \
  --network=lab-net --allow=tcp:80,tcp:443 --target-tags=web --source-ranges=0.0.0.0/0

# VM chính
gcloud compute instances create lab-web \
  --zone="$ZONE" --machine-type=e2-small \
  --subnet=lab-subnet --private-network-ip=10.10.0.10 \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --tags=web --metadata=enable-oslogin=FALSE \
  --create-disk=name=lab-web-data,size=10GB,type=pd-standard,device-name=data,auto-delete=yes

# VM backup
gcloud compute instances create lab-bkp \
  --zone="$ZONE" --machine-type=e2-small \
  --subnet=lab-subnet --private-network-ip=10.10.0.20 \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --metadata=enable-oslogin=FALSE \
  --create-disk=name=lab-bkp-data,size=10GB,type=pd-standard,device-name=data,auto-delete=yes
```

Nếu báo hết tài nguyên ở zone `b`, thử `-a` hoặc `-c`.

IP tĩnh (tùy chọn, xem chi phí ở 3.3):

```bash
# Cách dễ nhất: "nâng" IP đang dùng của VM thành IP tĩnh, KHÔNG làm đổi địa chỉ.
# Lấy IP hiện tại:
gcloud compute instances describe lab-web --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
# Giữ nguyên IP đó:
gcloud compute addresses create lab-web-ip --addresses=<IP_HIEN_TAI> --region="$REGION"
# Làm tương tự cho lab-bkp (lab-bkp-ip)

# Sau khi nộp bài, nhớ giải phóng để khỏi bị tính phí:
gcloud compute addresses delete lab-web-ip lab-bkp-ip --region="$REGION"
```

Tắt/bật VM khi không dùng:

```bash
gcloud compute instances stop  lab-web lab-bkp --zone="$ZONE"
gcloud compute instances start lab-web lab-bkp --zone="$ZONE"
```

Snapshot disk:

```bash
gcloud compute disks snapshot lab-web --zone="$ZONE" --snapshot-names=lab-web-clean
gcloud compute disks snapshot lab-web-data --zone="$ZONE" --snapshot-names=lab-web-data-clean
```

### 9.2 Swap 1 GB

```bash
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

### 9.3 Ổ data + fstab

```bash
ls -l /dev/disk/by-id/ | grep google-data           # tìm ổ data (device-name=data)
sudo mkfs.ext4 -L labdata /dev/disk/by-id/google-data
sudo mkdir -p /srv/data                              # VM2 dùng /srv/backup
sudo blkid /dev/disk/by-id/google-data               # lấy UUID
echo 'UUID=<uuid> /srv/data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a && df -h /srv/data
sudo reboot                                          # xác nhận vẫn mount
```

### 9.4 Tài khoản team: sudoers + script `add_user.sh`

Một lần mỗi VM:

```bash
sudo groupadd -f labadmin
echo '%labadmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-labadmin
sudo chmod 440 /etc/sudoers.d/90-labadmin
sudo visudo -cf /etc/sudoers.d/90-labadmin
```

> NOPASSWD vì user chỉ đăng nhập bằng khóa nên không có mật khẩu để sudo. Đánh đổi: ai chiếm được khóa của một thành viên sẽ có quyền root ngay. Ghi vào báo cáo; bù bằng passphrase cho khóa + fail2ban.

> **Bản chuẩn của script nằm trong repo** (`infra/vm/scripts/add_user.sh`, có `-h`, trap lỗi, qua shellcheck; dùng `-u <user> -f <file.pub>`). Đoạn dưới chỉ để tham khảo cách hoạt động.

`add_user.sh <username> "<public key>"` (chạy bằng tài khoản có sudo):

```bash
#!/usr/bin/env bash
# Thêm user cho thành viên và nạp public key. Dùng: ./add_user.sh an "ssh-ed25519 AAAA... an"
set -euo pipefail

user="${1:?usage: $0 <username> \"<public key>\"}"
key="${2:?missing public key}"

[[ "$user" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "username khong hop le" >&2; exit 1; }
[[ "$key" =~ ^ssh-ed25519\ AAAA[A-Za-z0-9+/=]+ ]] || { echo "key phai la public key ssh-ed25519" >&2; exit 1; }

if ! id "$user" >/dev/null 2>&1; then
  sudo adduser --disabled-password --gecos "" "$user"
fi
sudo usermod -aG labadmin "$user"

home="/home/$user"
sudo install -d -m 700 -o "$user" -g "$user" "$home/.ssh"
if ! sudo grep -qxF "$key" "$home/.ssh/authorized_keys" 2>/dev/null; then
  echo "$key" | sudo tee -a "$home/.ssh/authorized_keys" >/dev/null
fi
sudo chown "$user:$user" "$home/.ssh/authorized_keys"
sudo chmod 600 "$home/.ssh/authorized_keys"
echo "OK: $user"
```

Nhớ chạy `shellcheck add_user.sh` (đề yêu cầu mọi script qua shellcheck).

### 9.5 UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH-22'
sudo ufw allow 2222/tcp comment 'SSH-2222'
sudo ufw enable
sudo ufw status verbose
```

### 9.6 SSH hardening (`/etc/ssh/sshd_config.d/99-hardening.conf`)

```
Port 22
Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AllowUsers <user1> <user2> <user3> <user4> <user5>
MaxAuthTries 3
LoginGraceTime 30
```

```bash
sudo sshd -t && sudo systemctl reload ssh    # luôn kiểm tra cú pháp trước, giữ phiên cũ mở
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|allowusers'
```

`AllowUsers` lọc theo **tên user**, không phụ thuộc IP nên IP của team đổi liên tục không ảnh hưởng. Đề yêu cầu tối thiểu **một trong hai** {đổi cổng khác mặc định, `AllowUsers`}; D6 chọn `AllowUsers`. Lưu ý khi đặt `AllowUsers`: nút "SSH trên trình duyệt" của GCP dùng user theo tài khoản Google nên sẽ bị chặn nếu user đó không nằm trong danh sách. Giữ lại một tài khoản của TV1 trong `AllowUsers` và đảm bảo vào được trước khi đóng phiên cũ. Trên Ubuntu 22.04 ghi file trong `sshd_config.d/` được đọc **trước** nên cần kiểm tra bằng `sshd -T` xem giá trị cuối cùng có đúng không.

**Cổng 2222 không cần cấu hình sshd riêng** (dùng chung các thiết lập với cổng 22: cùng tắt root, tắt password, `AllowUsers`). Chỉ cần 3 việc: (1) mở ở VPC, (2) mở ở UFW, (3) thêm vào `port` của jail fail2ban (`port = 22,2222`). Thiếu việc (3) thì IP đã bị ban vẫn dò tiếp được cổng 2222, vì fail2ban chỉ chặn đúng các cổng nó được khai báo.

### 9.7 auditd

```bash
sudo apt -y install auditd audispd-plugins
sudo tee /etc/audit/rules.d/lab.rules <<'EOF'
-w /etc/passwd -p rwa -k passwd_access
-w /etc/shadow -p rwa -k shadow_access
EOF
sudo augenrules --load
sudo systemctl enable --now auditd

sudo cat /etc/shadow > /dev/null
sudo ausearch -k shadow_access -i | tail -20
```

### 9.8 Host key fingerprint để công bố cho team

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

### 9.9 Tránh tự khóa SSH và đường cứu hộ

Áp dụng cho mọi thay đổi SSH/UFW/VPC (`AllowUsers` thiếu user, mở nhầm cổng, và cả đổi cổng nếu sau này làm).

**Phòng tránh**
1. Snapshot disk trước khi sửa (P7.1).
2. Giữ phiên SSH cũ mở; test bằng phiên mới trước khi đóng.
3. `sudo sshd -t` trước khi reload.
4. Hẹn giờ tự hoàn tác, hủy nếu mọi thứ ổn:
   ```bash
   sudo apt -y install at
   echo 'rm -f /etc/ssh/sshd_config.d/99-hardening.conf; systemctl reload ssh' | sudo at now + 10 minutes
   atq            # xem job; sau khi test ổn: sudo atrm <id> để hủy
   ```
5. **Đã áp dụng (D6): hai cổng cùng lúc** (`Port 22` và `Port 2222`). Thứ tự bắt buộc: mở 2222 ở **VPC và UFW trước** → thêm `Port 2222` vào cấu hình → `sshd -t` → reload → test `ssh -p 2222` từ **phiên mới** → mới tính chuyện bỏ 22 (quyết định ở P9).

**Cứu hộ nếu vẫn bị khóa** (không cần SSH)
1. **VPC/UFW sai:** sửa rule VPC bằng `gcloud` được ngay. UFW sai thì dùng startup-script bên dưới để `ufw disable`.
2. **Startup-script** chạy bằng root mỗi lần VM boot, nên sửa được cấu hình SSH từ ngoài:
   ```bash
   gcloud compute instances add-metadata lab-web --zone="$ZONE" \
     --metadata=startup-script='#!/bin/bash
   rm -f /etc/ssh/sshd_config.d/99-hardening.conf
   ufw allow 22/tcp
   systemctl reload ssh'
   gcloud compute instances reset lab-web --zone="$ZONE"
   # xong thì gỡ script: gcloud compute instances remove-metadata lab-web --zone="$ZONE" --keys=startup-script
   ```
3. **SSH trên trình duyệt của Console:** mặc định dùng cổng 22 và user theo tài khoản Google (bị `AllowUsers` chặn nếu không có trong danh sách). Menu SSH của Console có tùy chọn cổng tùy chỉnh (kiểm tra lại khi dùng).
4. **Serial console:** cần tài khoản có mật khẩu local nên thường không dùng được ở setup này.
5. **Gắn disk sang VM tạm** để sửa file, hoặc **khôi phục từ snapshot** (P9.2).

### 9.10 Xem lịch sử làm việc của từng người

Mỗi người một user nên truy lại được ai làm gì ở nhiều mức:

| Muốn biết | Lệnh / nguồn |
|---|---|
| Ai đăng nhập, lúc nào, từ IP nào, bằng khóa nào | `sudo grep "Accepted publickey" /var/log/auth.log` hoặc `last -a` |
| Đăng nhập thất bại | `sudo lastb` hoặc `sudo grep "Failed" /var/log/auth.log` |
| Ai đang online | `w` |
| Ai chạy `sudo` lệnh gì | `sudo grep "COMMAND=" /var/log/auth.log`. Theo từng người: `sudo grep -E "sudo: +an :" /var/log/auth.log` (thay `an`) |
| Lịch sử lệnh gõ của một người | `sudo cat /home/<user>/.bash_history` |
| Lệnh chạy bằng quyền root theo từng người (cần luật auditd bên dưới) | `sudo ausearch -k root_cmds -ul $(id -u <user>) -i` |
| Ai sửa file nào trong repo | `git log --author=<tên>`, `git blame <file>` |
| Ai làm gì trên GCP (tạo VM, sửa firewall...) | Console → Logging → Logs Explorer → Cloud Audit Logs (Admin Activity) |

**Lưu lịch sử lệnh tốt hơn.** Mặc định `.bash_history` chỉ ghi khi thoát phiên, rớt mạng là mất. Tạo cho mọi user:

```bash
sudo tee /etc/profile.d/lab-history.sh <<'EOF'
# Lưu lịch sử ngay sau mỗi lệnh, kèm thời gian
export HISTTIMEFORMAT='%F %T '
export HISTSIZE=10000 HISTFILESIZE=20000
shopt -s histappend
PROMPT_COMMAND='history -a'"${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
```

**Ghi lệnh chạy bằng root theo từng người (auditd, tùy chọn).** Thêm vào `/etc/audit/rules.d/lab.rules` rồi `sudo augenrules --load`:

```
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_cmds
```

Mỗi lệnh chạy quyền root được ghi kèm `auid` (người đăng nhập gốc, kể cả khi qua `sudo`). Log tăng nhanh nên theo dõi dung lượng `/var/log/audit` (disk chỉ 10 GB); thấy ồn thì tắt trước demo.

**Giới hạn cần nói thật khi báo cáo.** Người có sudo NOPASSWD có thể sửa/xóa log và `.bash_history`, nên đây là dấu vết để truy lại chứ không chống chối bỏ tuyệt đối. Muốn mạnh hơn thì gửi log sang `lab-bkp` bằng rsyslog (tùy chọn, chưa làm).

---

## 10. Nhật ký tiến độ và thay đổi

| Ngày | Ai | Việc | Kết quả |
|---|---|---|---|
| (trước 18/11) | Trọng + Claude | Đọc đề, chia việc TV1, soạn kế hoạch, chốt các quyết định D2–D9, soạn hướng dẫn tạo SSH key | Có file kế hoạch đầu tiên |
| (trước 18/11) | Trọng | Gửi mail hỏi thầy Minh về việc dùng GCP | Thầy đồng ý (D1) |
| 2026-11-18 | Claude | Chọn cấu hình VM (e2-small × 2), viết file master này | Chưa dựng gì trên GCP. Việc tiếp theo: P0.1 |
| 2026-11-18 | Trọng + Claude | Ghi hạn nộp 3/12 22:00 + lộ trình đề xuất; tư vấn IP tĩnh (đề xuất reserve cả 2) và user riêng cho từng người (giữ D8) | Chờ Trọng xác nhận IP tĩnh |
| 2026-11-18 | Trọng + Claude | Chốt IP tĩnh (D10). Làm rõ `AllowUsers` không phụ thuộc IP. Thảo luận user riêng vs một user chung nhiều public key; thư mục nhóm `labadmin` chuyển thành tùy chọn | D8 (user riêng) đang chờ Trọng chốt lại |
| 2026-11-18 | Trọng + Claude | Thêm quy tắc 13 (thay đổi riêng của user phải báo/đưa lên cấp hệ thống), mục 8.5 (demo dùng user nào), mục 9.9 (tránh tự khóa SSH, cứu hộ) | Mặc định giữ D8 (user riêng) cho đến khi Trọng đổi |
| 2026-11-18 | Trọng + Claude | Chốt dùng **hai cổng SSH 22 + 2222** ngay từ đầu (sửa D6, P1.3, P6.2, P7.3, P7.7, 7.2, 9.1, 9.5, 9.6, 9.9). Thêm 8.6 (quyền quản trị), 9.10 (xem lịch sử từng người), D11 | D11 đề xuất, chờ Trọng chốt; quyết định đóng 22 để P9 |
| 2026-11-18 | Trọng + Claude | Chốt D8 (user riêng) và D12 (demo AllowUsers, mục 8.7). Cổng 2222 là cổng dự phòng, 22 dùng hằng ngày (đã sửa 7.2, bảng UFW). Tạo repo skeleton `infra/` (mục 12), shellcheck sạch, test dry-run | Skeleton chưa chạy trên GCP thật. Việc tiếp theo vẫn là P0.1 |
| 2026-11-19 | Trọng + Claude | Đổi tên VM bỏ hậu tố `01`: `lab-web` (chính) và `lab-bkp` (backup). Cập nhật toàn bộ repo, file master, hướng dẫn SSH; shellcheck vẫn sạch | Chưa tạo VM nào trên GCP nên không ảnh hưởng gì |
| 2026-11-20 | Trọng | Dựng project `manger-vms`, VPC `lab-net`, 3 firewall rule, 2 VM (`lab-web` `34.126.146.150`, `lab-bkp` `34.87.119.173`); chạy `bootstrap.sh -u` & `mount-data.sh` trên cả 2 VM, reboot xác nhận; tạo user `trong` trên `lab-web`, lấy host key fingerprint cả 2 VM, chụp 6 ảnh vào `evidence-TV1/` | Xong P0–P3 (chờ xác nhận P0.3, P1.5, P2.4). Đang chờ public key TV2–TV5 cho P4 |
| 2026-11-20 | Trọng | Reserve IP tĩnh cho cả 2 VM (`03-static-ip.sh`); thêm user `trong` trên `lab-bkp`; bật UFW trên cả 2 VM (`ufw-setup.sh -w` trên `lab-web`, `ufw-setup.sh` trên `lab-bkp`); cập nhật IP & fingerprint vào `HUONG_DAN_SSH.md` | Xong P2.4, P4.1–P4.2, P6.1–P6.4. Tiếp theo: cài `auditd` (P8) và chờ key TV2–TV5 |

---

## 11. Vấn đề còn mở / rủi ro

- [ ] Hạn nộp đã có (3/12 22:00). Còn thiếu **ngày demo**, cần hỏi nhóm/xem lịch.
- [~] **Repo Git**: đã tạo repo và push skeleton, cần điền URL vào mục 4.
- [x] **IP tĩnh**: đã chốt reserve cả 2 VM (D10), xóa sau khi nộp bài.
- [ ] Tên và username của TV5, khóa public của TV2–TV5 chưa thu.
- [ ] Credit chỉ còn khoảng $90: cần lịch tắt/bật VM và theo dõi billing.
- [ ] Kênh cảnh báo (msmtp/Telegram) cần chốt sớm vì cổng 25 bị chặn.
- [ ] Cổng 22 mở cho mọi IP sẽ bị bot dò ngay khi VM lên: cần P7 + fail2ban (TV2) nhanh.
- [ ] **Có đóng cổng 22 ở cuối không** (quyết định ở P9)? Đóng thì mới tính là "đổi cổng" và giảm bot dò, nhưng mất SSH trình duyệt của GCP làm đường cứu (vẫn còn startup-script ở 9.9). `AllowUsers` đã đủ yêu cầu của đề nên đóng hay không là tùy.
- [ ] Demo phụ thuộc Internet: chuẩn bị hotspot dự phòng.
- [ ] Giả định cần kiểm tra khi làm thật: kích thước tối thiểu ổ data 10 GB, giá e2-small ở Singapore, chi phí IPv4 external.

---

## 12. Repo skeleton của TV1 (`infra/`)

Skeleton nằm trong `linux-final-project-skeleton.tar.gz`: giải nén, `git init`, push lên repo chung. Trạng thái: **DRAFT**. Đã qua `shellcheck` sạch, `bash -n`, `-h`, dry-run với gcloud giả và kiểm tra đầu vào; **chưa chạy trên GCP/VM thật** nên test từng script và sửa nếu lỗi.

```
linux-final-project/
├── README.md              skeleton theo Mục 1.3 (hướng đồ án, sơ đồ VM, phân công, cách tái tạo)
├── .gitignore             chặn env.sh, khóa, *.pem, *.key
├── .shellcheckrc          external-sources + source-path=SCRIPTDIR
├── infra/                 (TV1)
│   ├── lib/               common.sh (log, die, trap, dry-run), gcp.sh
│   ├── gcp/               env.sh.example, 01-network, 02-vms, 03-static-ip, snapshot, 99-teardown
│   ├── vm/scripts/        bootstrap, mount-data, add_user, ufw-setup, harden-ssh, install-auditd
│   ├── vm/etc/            99-hardening.conf, lab.rules, lab-rootcmds.rules, 90-labadmin, lab-history.sh
│   └── evidence/          README: danh sách ảnh chụp cần có
├── proxy/  app/  db-backup/  tools/    placeholder cho TV2–TV5 (mỗi thư mục có README ghi việc)
```

Điểm cần biết:
- Mọi script có `-h`, `set -Eeuo pipefail`, trap ERR/EXIT, log rõ, đúng yêu cầu của đề (Mục 2.4, 5.1). `-n` là dry-run cho các script gcloud.
- `harden-ssh.sh` có chống tự khóa: bắt buộc người chạy nằm trong `AllowUsers`, cổng trong cấu hình phải đã mở ở UFW, `sshd -t` lỗi thì tự hoàn tác.
- `mount-data.sh` **không format** nếu ổ đã có filesystem.
- `99-teardown.sh` xóa toàn bộ tài nguyên GCP (hỏi gõ `XOA`), chạy sau khi nộp bài.
- Thứ tự chạy chi tiết nằm trong `infra/README.md`.
- TV5 có thể dùng lại `infra/lib/common.sh` cho script của mình (hoặc sao chép sang `tools/` để mỗi phần tự chứa).
