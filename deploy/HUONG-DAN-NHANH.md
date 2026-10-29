# Triển khai nhanh — thuetab.hidev.dev

| Phần | Chạy ở | Địa chỉ |
|---|---|---|
| Web (giao diện) | Cloudflare Pages | `https://thuetab.hidev.dev` |
| API + worker + game | Debian 12/13 có Docker, uvicorn `0.0.0.0:8080`, ra Internet qua Cloudflare Tunnel | `https://api-thuetab.hidev.dev` |
| App Android / Windows / Linux / macOS | gắn sẵn API | tải ở trang **Tải ứng dụng** |
| iOS và máy chưa có bản cài | cài web như ứng dụng (PWA) | `https://thuetab.hidev.dev` |

> Dùng `api-thuetab.hidev.dev` (không phải `api.thuetab.hidev.dev`): SSL miễn phí của Cloudflare chỉ phủ subdomain một cấp.

## 1. Backend trên Debian (~10 phút)

**Tạo tunnel** (Cloudflare → Zero Trust → Networks → Tunnels → Create → Cloudflared):
- Đặt tên `thuetab`, chép **token** ở bước cài đặt.
- Public hostname: `api-thuetab.hidev.dev` → Service `HTTP` → `localhost:8080`.

**Trên máy Debian** (cần sẵn Docker):
```bash
git clone https://github.com/hoangtuvungcao/ThueTab.git && cd ThueTab
sudo bash deploy/install-debian.sh \
  --origin https://thuetab.hidev.dev \
  --listen 0.0.0.0 --port 8080 \
  --cf-token <TOKEN_TUNNEL>
```
Script tự: cài Python, build image game, tính số tab theo RAM/CPU, SQLite, zram, dịch vụ `thuetab-api`,
`thuetab-worker`, `cloudflared`, và hỏi email để tạo admin.

Kiểm tra: `curl https://api-thuetab.hidev.dev/api/health` → `{"ok":true}`.
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
| Environment variable | `VITE_API_BASE` = `https://api-thuetab.hidev.dev` |

Sau khi build xong: Custom domains → thêm `thuetab.hidev.dev`. Mỗi lần push lên GitHub, Pages tự build lại.

## 3. Ứng dụng cài đặt
Trên máy build (có Godot 4.7.2 + export templates, Android SDK, Java):
```bash
bash scripts/build-apps.sh --api https://api-thuetab.hidev.dev --godot /đường/dẫn/Godot_v4.7.2
scp exports/ThueTab-* <debian>:/opt/thuetab/data/downloads/
```
Trang **Tải ứng dụng** tự nhận bản mới nhất mỗi nền tảng và gợi ý theo máy người xem; iOS luôn hướng dẫn
"Chia sẻ → Thêm vào Màn hình chính". Khoá ký Android nằm ở `data/android-release.keystore` +
`data/android-keystore.txt` — **sao lưu và giữ bí mật**, mọi bản cập nhật APK phải dùng đúng khoá này.

## 4. Nạp tiền SePay
Webhook: `https://api-thuetab.hidev.dev/api/payments/sepay`, xác thực API Key (≥32 ký tự).
Điền `SEPAY_API_KEY`, `SEPAY_API_TOKEN`, `BANK_*` trong `/opt/thuetab/.env` rồi khởi động lại API.
Chi tiết: mục "Nạp tiền SePay" trong `deploy/README.md`.

## Cập nhật phiên bản
```bash
cd ~/ThueTab && git pull && sudo bash deploy/install-debian.sh --origin https://thuetab.hidev.dev --listen 0.0.0.0 --port 8080
```
(giữ nguyên `.env`, dữ liệu và tài khoản; image game mới được build lại và mọi tab tự chuyển sang.)
