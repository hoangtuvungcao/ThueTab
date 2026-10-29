# Triển khai nhanh — API thuetab.hidev.dev · Web trên Cloudflare Pages

| Phần | Chạy ở | Địa chỉ |
|---|---|---|
| API + worker + game | Debian 12/13 có Docker, uvicorn `0.0.0.0:8080`, ra Internet qua Cloudflare Tunnel | `https://thuetab.hidev.dev` |
| Web (giao diện) | Cloudflare Pages, domain mặc định | `https://<tên-project>.pages.dev` (ví dụ `thuetab.pages.dev`) |
| App Android / Windows / Linux / macOS | gắn sẵn API | tải ở trang **Tải ứng dụng** |
| iOS và máy chưa có bản cài | cài web như ứng dụng (PWA) | `https://<tên-project>.pages.dev` |

> Web và API ở hai site khác nhau (`pages.dev` ≠ `hidev.dev`), nên web đăng nhập bằng token (không dùng
> cookie) — chạy được cả trên Safari/iPhone. `PUBLIC_ORIGIN` phải ghi **đúng** domain Pages.

## 1. Backend trên Debian (~10 phút)

**Tạo tunnel** (Cloudflare → Zero Trust → Networks → Tunnels → Create → Cloudflared):
- Đặt tên `thuetab`, chép **token** ở bước cài đặt.
- Public hostname: `thuetab.hidev.dev` → Service `HTTP` → `localhost:8080`.

**Trên máy Debian mới** (script tự cài Docker, Python… — chạy bằng root):
```bash
apt-get update -qq && apt-get install -y -qq git && git clone https://github.com/hoangtuvungcao/ThueTab.git && cd ThueTab
bash deploy/install-debian.sh \
  --origin https://thuetab.pages.dev \
  --listen 0.0.0.0 --port 8080 \
  --cf-token <TOKEN_TUNNEL>
```
Script tự: cài Python, build image game, tính số tab theo RAM/CPU, SQLite, zram, dịch vụ `thuetab-api`,
`thuetab-worker`, `cloudflared`, và hỏi email để tạo admin.

Kiểm tra: `curl https://thuetab.hidev.dev/api/health` → `{"ok":true}`.
Nhật ký: `journalctl -u thuetab-api -u thuetab-worker -f`. Cấu hình: `/opt/thuetab/.env` (sửa xong
`sudo systemctl restart thuetab-api thuetab-worker`).

> `--listen 0.0.0.0` mở cổng 8080 ra mạng LAN. Nếu chỉ dùng tunnel, có thể chặn cổng này bằng tường lửa
> (`ufw deny 8080`) — tunnel vẫn chạy vì nó kết nối từ trong máy ra.

## 2. Web trên Cloudflare Pages (~3 phút)
Workers & Pages → Create → Pages → Connect to Git → chọn repo `ThueTab`:

| Mục | Giá trị |
|---|---|
| Framework preset | None |
| Build command | `npm --prefix web ci && npm --prefix web run build` |
| Build output directory | `web/dist` |
| Root directory | *(để trống)* |
| Environment variables | `VITE_API_BASE` = `https://thuetab.hidev.dev`, `NODE_VERSION` = `20` |

Đặt tên project (ví dụ `thuetab`) → web ở `https://thuetab.pages.dev`. Nếu tên đã có người dùng, Pages sẽ
thêm hậu tố — khi đó sửa `PUBLIC_ORIGIN` trong `/opt/thuetab/.env` cho đúng rồi `sudo systemctl restart thuetab-api`.
Mỗi lần push lên GitHub, Pages tự build lại.

## 3. Ứng dụng cài đặt
Trên máy build (có Godot 4.7.2 + export templates, Android SDK, Java):
```bash
bash scripts/build-apps.sh --api https://thuetab.hidev.dev --godot /đường/dẫn/Godot_v4.7.2
scp exports/ThueTab-* <debian>:/opt/thuetab/data/downloads/
```
Trang **Tải ứng dụng** tự nhận bản mới nhất mỗi nền tảng và gợi ý theo máy người xem; iOS luôn hướng dẫn
"Chia sẻ → Thêm vào Màn hình chính". Khoá ký Android nằm ở `data/android-release.keystore` +
`data/android-keystore.txt` — **sao lưu và giữ bí mật**, mọi bản cập nhật APK phải dùng đúng khoá này.

## 4. Nạp tiền SePay
Webhook: `https://thuetab.hidev.dev/api/payments/sepay`, xác thực API Key (≥32 ký tự).
Điền `SEPAY_API_KEY`, `SEPAY_API_TOKEN`, `BANK_*` trong `/opt/thuetab/.env` rồi khởi động lại API.
Chi tiết: mục "Nạp tiền SePay" trong `deploy/README.md`.

## Cập nhật phiên bản
```bash
cd ~/ThueTab && git pull && sudo bash deploy/install-debian.sh --origin https://thuetab.pages.dev --listen 0.0.0.0 --port 8080
```
(giữ nguyên `.env`, dữ liệu và tài khoản; image game mới được build lại và mọi tab tự chuyển sang.)

## Lưu ý tunnel
Một tunnel chỉ nên có **một** nơi chạy `cloudflared` cho ứng dụng này. Nếu tunnel `thuetab` đang chạy ở máy khác
(ví dụ Windows), khi chuyển sang VPS hãy gỡ bản cũ (`cloudflared service uninstall` trên máy đó), nếu không
Cloudflare chia lượng truy cập giữa hai máy và một nửa request sẽ lỗi. Token: Tunnels → `thuetab` →
**Add a replica** → chép phần `eyJ…` trong lệnh `cloudflared service install eyJ…`.
