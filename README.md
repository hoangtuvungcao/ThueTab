# ThuêTab

Thuê "tab" để treo game Java 24/24 trên máy chủ: game J2ME (điện thoại Nokia) và game Java PC chạy trong container
riêng, người dùng xem màn hình trực tiếp và bấm phím từ web hoặc app trên điện thoại/máy tính.

| Phần | Công nghệ | Chạy ở |
|---|---|---|
| API + thanh toán | FastAPI (`backend/`), SQLite hoặc PostgreSQL | Máy Debian (VM/VPS), ra Internet qua Cloudflare Tunnel |
| Worker + game | `runner/worker.py`, Docker, MicroEmulator, stream H.264 | Cùng máy với API |
| Web | React + Vite (`web/`) | Cloudflare Pages (tự build khi đẩy lên GitHub) |
| App | Godot 4.7 (`native/`) — Android, Windows, Linux, macOS | Phát hành trên GitHub Releases |

Hiện đang chạy: web https://thuetab.pages.dev · API https://thuetab.hidev.dev.

![Web trên điện thoại](docs/web-mobile.png) ![App Godot](docs/godot-mobile.png)

## Tính năng chính
- Thuê tab theo gói (ngày/tuần/tháng), gia hạn, nhóm tab, hẹn giờ khởi động lại, chia sẻ quyền xem/chơi.
- Tải lên file `.jar` của mình (tự nhận J2ME hay Java PC), đổi tên file, đổi game của tab bất cứ lúc nào.
- Màn hình game trực tiếp 30/60 FPS, bàn phím Nokia (phím mềm, `*`, `#`), gõ chữ vào game, xem nhiều màn hình cùng lúc.
- Ví nạp tiền qua chuyển khoản ngân hàng (SePay, tự cộng tiền), mã khuyến mãi, giới thiệu bạn bè.
- Trang Quản trị: người dùng, tab, file JAR, worker, nội dung trang, bảng giá, thông báo, bảo trì.
- Giao diện sáng/tối, dùng tốt trên điện thoại (web cài được như ứng dụng — PWA — cho iPhone).

## Cài máy chủ (Debian 12/13)
Chạy bằng root trên máy mới; script tự cài Docker, Python, build image game, tạo dịch vụ và hỏi email admin:
```bash
apt-get update -qq && apt-get install -y -qq git
git clone https://github.com/hoangtuvungcao/ThueTab.git && cd ThueTab
bash deploy/install-debian.sh --origin https://thuetab.pages.dev --listen 0.0.0.0 --port 8080 --cf-token <TOKEN_TUNNEL>
```
Cập nhật bản mới (code server + image game + app trên trang tải về):
```bash
cd ~/ThueTab/ThueTab && git pull && bash deploy/install-debian.sh --origin https://thuetab.pages.dev --listen 0.0.0.0 --port 8080
```
Chi tiết: [deploy/HUONG-DAN-NHANH.md](deploy/HUONG-DAN-NHANH.md) (Cloudflare Tunnel + Pages) và
[deploy/README.md](deploy/README.md) (Docker Compose + PostgreSQL + Caddy, tài nguyên mỗi tab, sao lưu).

## Chạy thử trên máy mình
Cần Python 3.11+, Node 20+, Docker:
```bash
python scripts/local.py --setup   # lần đầu: venv, npm, build web, image game, tài khoản admin (data/LOCAL_LOGIN.txt)
python scripts/local.py           # chạy API + worker
```
Phát triển web: `cd web && npm run dev`. Test API: `.venv/bin/python -m pytest -q backend/tests`.

## Build app
```bash
bash scripts/build-apps.sh --api https://thuetab.hidev.dev --godot /đường/dẫn/Godot_v4.7 [--only Android,Linux]
```
File ra ở `exports/`. Phiên bản app đặt trong `scripts/prepare-native.py`. Phát hành bằng
`gh release create vX.Y.Z exports/ThueTab-*`; máy chủ lấy bản mới bằng `scripts/fetch-apps.sh`
(bộ cài chạy sẵn bước này). Bản Android cần `data/android-release.keystore` — giữ kỹ, mất là không cập nhật đè được.

## Cấu trúc
```
backend/   API FastAPI, stream, test (backend/tests)
runner/    worker, image game (Dockerfile.game), start-game.sh
web/       giao diện React
native/    app Godot (Main.gd, pages/, ui.gd)
design/    token giao diện + hợp đồng API dùng chung web/app
deploy/    bộ cài Debian, systemd, Caddy, hướng dẫn
scripts/   chạy local, build/tải app, quản trị (manage.py), sao lưu, tường lửa
```

## Bảo mật
Không đưa lên git: `.env`, thư mục `data/` (database, keystore Android, file đăng nhập). Cấu hình mẫu: `.env.example`.
