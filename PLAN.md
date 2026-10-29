# ThuêTab — kế hoạch thực hiện

Mục tiêu: web responsive + app Godot dùng chung API; treo Java trong container giới hạn tài nguyên, thuê theo thời hạn, ví SePay, admin trên mọi thiết bị.

## Các bước
1. API FastAPI, PostgreSQL production / SQLite thử local; tài khoản Argon2, session, RBAC, nhật ký.
2. Web React: dashboard, tạo/đổi tên/dừng/chạy tab, màn hình game, ví/QR, giá, trợ giúp và admin.
3. Thanh toán SePay: API key, kiểm tra ngân hàng/tài khoản/chiều tiền/mã/giá trị, unique transaction, transaction DB nguyên tử.
4. Worker Docker: catalog được duyệt, CPU/RAM/PID, filesystem readonly, không đặc quyền, timeout và tự dừng hết hạn. Demo Java tự viết; J2ME cần emulator/bản game được cấp phép riêng.
5. Godot: UI thích ứng, đăng nhập, thuê tab, ví, màn hình/điều khiển game và admin dùng cùng backend.
6. Test API/security/concurrency, build web, chạy Godot headless, chạy demo thật Docker; tài liệu setup/backup/mở rộng.

## Quyết định sản phẩm
- Giá khởi điểm cấu hình được: 500đ/ngày, 3.000đ/tuần, 9.000đ/tháng cho 1 tab 512 MiB/0,5 vCPU. Đây là giả định kinh doanh, cần đo thực tế và tính điện/VPS/băng thông/SePay trước khi bán.
- Dùng thử 60 phút, 1 tab: admin cấp quyền sau xác minh; mỗi tài khoản chỉ nhận một lần. Không tự cấp hàng loạt tài khoản chưa xác minh. Không có kỹ thuật chống đa tài khoản tuyệt đối.
- Thuê trả trước, không tự gia hạn ngầm, dừng không hoàn lại thời gian; gia hạn chủ động. Không tính phí khi worker chưa online/còn chỗ.
- Chỉ admin cấu hình game đã duyệt. Không thực thi JAR tải lên tùy ý trên host.
- Mặc định game không có mạng; cần mở đúng server game qua chính sách egress trước khi phục vụ game online.
- Chạy local trước theo yêu cầu người dùng. Không công bố dịch vụ, không thu tiền thật trong phiên này.

## Điều kiện trước vận hành công khai
HTTPS, cấu hình ngân hàng/SePay, kiểm thử webhook thật, emulator/game thực tế, chính sách mạng theo game, backup/restore, tải thực tế và ký app Android/iOS. Không hứa không lag hoặc bảo mật tuyệt đối.

## Cập nhật 2026-10-29
- Chạy game J2ME thật: image `thuetab-java:local` có MicroEmulator 2.0.4 (+ Nokia UI, JSR-135), khung hình 240×320. API đọc manifest JAR khi tải lên (`MIDlet-1` → J2ME, `Main-Class` → Java PC).
- JAR tự duyệt (`JAR_AUTO_APPROVE=true`), admin vẫn chặn được. Nạp tiền giả lập và tài khoản demo chỉ có khi `DEV_MODE=true`.
- Tính năng ngang các dịch vụ cloud phone: xem nhiều màn hình, điều khiển đồng bộ nhiều tab, gõ chữ vào game, phím mềm/`*`/`#`, gia hạn tự động (tuỳ chọn), số liệu trạng thái thật (`/api/status`).
- Web và Godot dùng chung `design/tokens.json` + hợp đồng API `design/README.md`.

## Lộ trình chưa làm
- Android (cloud phone): cần host Linux có module kernel binder/ashmem để chạy Redroid, GPU nếu game nặng, mỗi máy 2–4 GB RAM → giá phải cao hơn nhiều so với tab Java.
- PC Windows: cần VM (KVM) + giấy phép Windows cho từng máy; không chạy được trong container Linux hiện tại.
- Kiểm thử với file JAR game thật (NSO, Avatar…) có mạng: mở egress đúng server game và đo RAM/CPU thực tế.
