# proxy/ (TV2: An)
Nginx reverse proxy, ≥ 2 virtual host, HTTPS tự ký (openssl), redirect 80 → 443, fail2ban cho SSH (`port = 22,2222`).
Đặt file cấu hình thật vào đây (vd: `nginx/sites-available/*.conf`, `fail2ban/jail.local`).
