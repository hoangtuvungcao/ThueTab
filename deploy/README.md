# Triển khai production

Một máy Linux có Docker. API + PostgreSQL chạy bằng Docker Compose, worker chạy trên host (cần Docker socket),
Caddy làm HTTPS. API phải chạy **một tiến trình** (stream video giữ trong bộ nhớ) — đúng như `Dockerfile`.

1. Mã nguồn tại `/opt/thuetab`, tạo user `thuetab` thuộc nhóm `docker`.
2. `cp .env.example .env`, điền: mật khẩu DB, `WORKER_TOKEN` (≥32 ký tự ngẫu nhiên), `PUBLIC_ORIGIN=https://<tên miền>`,
   `COOKIE_SECURE=true`, thông tin ngân hàng + `SEPAY_API_KEY` (webhook) + `SEPAY_API_TOKEN` (quét dự phòng), liên hệ hỗ trợ.
3. `mkdir -p data && sudo chown 10002 data` rồi `docker compose up -d --build`.
4. Image game: `docker build -f runner/Dockerfile.game -t thuetab-java:local .`
5. Worker: `python3 -m venv .venv && .venv/bin/pip install -r backend/requirements.txt`,
   chép `deploy/thuetab-worker.service` vào `/etc/systemd/system/`, `systemctl enable --now thuetab-worker`.
6. Admin đầu tiên: `docker compose exec api python scripts/manage.py create-admin --email <email>`.
7. HTTPS: cài Caddy, dùng `deploy/Caddyfile` (đổi tên miền). Webhook SePay: `https://<tên miền>/api/payments/sepay`.
8. Tường lửa cho container game: `sudo bash scripts/setup-firewall.sh` (chặn LAN, SMTP, SSH, cổng đào coin).
9. Sao lưu theo lịch (cron): `docker compose exec -T db pg_dump -U thuetab thuetab | gzip > backup-$(date +%F).sql.gz`
   và chép thư mục `data/jars`. (`scripts/backup.py` chỉ dành cho SQLite khi chạy thử local.)

Kiểm tra sau triển khai: `curl https://<tên miền>/api/health`, đăng nhập admin, thuê tab, tải JAR, mở màn hình
(stream 30/60 FPS), chuyển khoản thử 10.000đ và xem tiền tự cộng.

Gỡ tài khoản: `python scripts/manage.py delete-user --email <email>` (không xoá được admin).

## Phát hành ứng dụng (trang "Tải ứng dụng")
1. `python scripts/prepare-native.py`, mở `.staging/native` bằng Godot 4.7 và export từng nền tảng
   (trước đó sửa `native/client.json` → `"api_url": "https://<tên miền>"`).
2. Chép file vào `data/downloads/` với đuôi đúng: `.exe`/`.msi` (Windows), `.apk` (Android),
   `.x86_64`/`.AppImage`/`.tar.gz` (Linux), `.dmg`/`.zip` (macOS). Trang web tự nhận bản mới nhất mỗi nền tảng
   và đề xuất theo hệ điều hành/trình duyệt của người xem. Không có bản nào → chỉ hiện cách cài web như ứng dụng (PWA).

## Nội dung & bảng giá
Admin sửa trong Quản trị → "Nội dung & cài đặt": thông báo, tiêu đề, FAQ, liên hệ hỗ trợ, bảng giá, mức nạp nhanh.
Thay đổi có hiệu lực ngay trên web và ứng dụng, không cần build lại.

## Tài nguyên & tối ưu (đo với Ninja School, 240×320)
- Mỗi tab: ~85–95 MB RAM, ~6–8% một nhân CPU khi không ai xem; giới hạn cứng 512 MB / 0,5 vCPU / 96 tiến trình.
- Chỉ quay màn hình khi có người xem: 30/60 FPS cho người đang chơi, 2 FPS cho ảnh thu nhỏ (danh sách tab, đa màn hình),
  không quay gì khi không ai mở. Khung hình trùng (màn đứng yên) bị bỏ trước khi nén → ít CPU và băng thông hơn ~60%.
- 60 FPS không lọc khung tốn gần hết 0,5 vCPU của tab → mặc định 30 FPS; màn HD (640×360) đạt ~10–20 FPS.
- Image game 383 MB dùng chung cho mọi tab (JRE rút gọn bằng jlink + CDS, FFmpeg tự build chỉ gồm x11grab/MJPEG/PNG).
  Sau khi build lại image, khởi động lại worker: mọi tab tự chuyển sang image mới.
- Ước tính thận trọng: máy 8 GB RAM / 4 nhân chạy ~30–35 tab (CPU là giới hạn trước RAM); cần đo lại với game thật đang online.

## Cloudflare (gói miễn phí)
Cloudflare chỉ đứng phía trước — API, worker và game vẫn chạy trên VPS/máy của bạn.
- **Proxy (đám mây cam)**: trỏ DNS tên miền về VPS, bật proxy → HTTPS miễn phí, ẩn IP VPS, cache file `/assets`
  (đã có header cache dài hạn). Chặn cổng 80/443 trên VPS chỉ cho dải IP Cloudflare nếu muốn ẩn hẳn.
- **Hoặc Tunnel** (không cần mở cổng, chạy được cả máy ở nhà): `cloudflared tunnel create thuetab`, route tên miền tới
  `http://127.0.0.1:8000`. WebSocket (stream game) đi qua bình thường.
- IP thật của người dùng lấy từ `CF-Connecting-IP`/`X-Forwarded-For`, chỉ tin khi kết nối đến từ `TRUSTED_PROXIES`
  (mặc định localhost + mạng Docker) — giới hạn đăng nhập theo từng người, không bị gộp chung IP proxy.
- Lưu ý điều khoản: gói miễn phí không dành cho truyền video/dung lượng lớn. Stream game là chuỗi ảnh JPEG; nếu đông
  người xem, cân nhắc đặt stream ở tên miền con không bật proxy (DNS only) để tránh vi phạm.
