# ThuêTab — hệ thống thiết kế & hợp đồng API dùng chung

Web (`web/`) và app Godot (`native/`) là hai client của **cùng một API**. Mọi màu sắc, nhãn trạng thái,
thứ tự menu và chu kỳ làm mới lấy từ `design/tokens.json` — sửa ở đó, cả hai client đổi theo.

## Nguyên tắc
- **Sản phẩm thật, không demo/dev.** Không có badge DEV, tài khoản demo, nút "giả lập", số phiên bản, RAM/CPU,
  tên máy chủ, IP, cổng hay đường dẫn trên bất kỳ màn hình nào. App Godot không có ô nhập địa chỉ server.
- **Game là tuỳ chọn khi thuê.** `POST /tabs` không cần `game`; tab chưa có game ở trạng thái `idle`
  ("Chưa chọn game") và hiện nút "Chọn game" nổi bật. `config.games` chỉ chứa game đang mở (hiện tại: `custom-jar`).
- Chỉ hiển thị số liệu thật từ API. Không ping, uptime, số người online, đánh giá hay liên hệ giả.
- Liên hệ hỗ trợ lấy từ `config.support` (để trống thì ẩn).
- Game có `enabled=false` hiển thị "Sắp có" kèm `note`, không cho chọn.
- **Tab ≠ game.** Tab là một máy treo đã thuê; người dùng đổi game/JAR của tab bất cứ lúc nào (PATCH `game`,
  `custom_jar_id`), tab tự khởi động lại với game mới. Nút "Đổi game" phải luôn có trên thẻ tab và trong màn xem.
- **Không lộ hệ thống.** Không hiển thị worker/máy chủ, container, IP, đường dẫn, mã băm nội bộ cho người dùng
  thường. Chỉ trang Quản trị được thấy worker. Thông báo lỗi dùng nguyên `detail` từ API.
- Nạp tiền: hiện QR (`qr_url`) + ngân hàng/số tài khoản/tên/nội dung, tự cập nhật khi tiền vào.
  Nếu `config.payment_ready=false`: hiện "Nạp tiền đang tạm ngưng" (không nói lý do kỹ thuật).

## API (tiền tố `/api`, JSON, lỗi trả `{detail: "thông báo tiếng Việt"}`)
Xác thực: web dùng cookie `tt_session` (httponly); Godot dùng `Authorization: Bearer <token>` từ login.

| Method | Path | Ghi chú |
|---|---|---|
| GET | `/config` | site{announcement,hero_title,hero_subtitle,cta,features[{title,text}],steps[{title,text}],faq[{q,a}],footer} (admin sửa được), screens[{id,label,orientation}], downloads[], support{zalo,telegram,facebook,email,hotline}, topup_presets[], auto_topup (true = tiền tự cộng sau khi chuyển khoản), jar_auto_approve, plans[{id,name,days,price}], games[{id,name,kind,description,enabled,icon,note}], payment_ready, is_live_payment, trial_minutes, max_tabs, jar_max_mb, support{zalo,telegram,email} |
| GET | `/api/downloads/{file}` | tải bản cài app (danh sách ở `config.downloads[{platform,label,file,size,updated,url}]`) |
| GET | `/status` | công khai: {online, accepting} — chỉ để hiện "Sẵn sàng / Tạm hết chỗ / Bảo trì" |
| POST | `/auth/register` | {email,password(≥10),name} |
| POST | `/auth/login` | {email,password} → {user, token} |
| POST | `/auth/logout` | |
| POST | `/auth/logout-all` | đăng xuất mọi thiết bị |
| GET | `/me` | id,email,name,role,balance,blocked,trial_approved,trial_used,created |
| PATCH | `/me` | {name} |
| PATCH | `/me/prefs` | cài đặt cá nhân, đồng bộ web↔app; `/me` trả `prefs`. Khoá & giá trị: theme dark/light/system, accent neon/violet/emerald/amber/rose (`tokens.accents`), font_scale 90/100/110/125, density comfortable/compact, reduce_motion, default_fps 30/60, show_fps, keypad_size sm/md/lg, haptics, sounds, default_screen (id trong `config.screens`), start_page, wall_columns auto/2/3/4, expiry_alert_hours 0/6/12/24/48 |
| POST | `/me/password` | {old,new(≥10)} — đăng xuất các thiết bị khác |
| GET | `/tabs` | [{id,name,game,plan,desired,status,error,expires,created,slot_id,custom_jar_id,auto_renew}] |
| POST | `/tabs` | {name,plan,game?,custom_jar_id?,trial?,slot_id?} — bỏ trống game để chọn sau |
| PATCH | `/tabs/{id}` | {screen} xoay/đổi kích thước màn hình game (tab khởi động lại), {game, custom_jar_id?} đổi game/JAR (tab khởi động lại), {name?}, {desired:'running'\|'stopped'}, {auto_renew: bool} (gia hạn tự động từ ví trong 1 giờ cuối; tự tắt khi thiếu tiền) |
| POST | `/tabs/{id}/renew` | {plan} |
| DELETE | `/tabs/{id}` | chỉ khi desired=stopped và status ∈ stopped/expired/error |
| GET | `/tabs/{id}/frame` | PNG: game J2ME 240×320 (dọc), Java PC 640×480; 404 khi chưa có hình mới |
| POST | `/tabs/{id}/input` | {key} ∈ Up Down Left Right Return Escape space BackSpace F1 (phím mềm trái) F2 (phím mềm phải) asterisk (*) numbersign (#) 0–9 |
| POST | `/tabs/{id}/tap` | {x,y} chạm, thêm {x2,y2} = vuốt. Toạ độ theo pixel của ảnh frame (J2ME = `tab.screen`, PC 640×480) |
| POST | `/tabs/{id}/text` | {text} 1–64 ký tự ASCII in được — gõ chữ vào ô nhập trong game (đăng nhập…) |
| POST | `/tabs/input` | {tab_ids[≤20], key} — điều khiển đồng bộ nhiều tab → {sent} |
| GET | `/tabs/{id}/logs` | {logs,status,updated} — đã che IP/đường dẫn |
| GET/POST | `/slots`, `/slots/{id}/renew` | mua slot trống {quantity,plan} |
| GET | `/jars` | [{id,filename,file_size,sha256,status,kind:'midp'\|'jar',midlet,created}] — kind=midp là game J2ME (chạy MicroEmulator) |
| POST | `/jars/upload` | body nhị phân, header `X-Filename` (URL-encoded), tối đa 30MB |
| DELETE | `/jars/{id}` | 409 nếu còn tab dùng file này (thông báo nêu tên tab) |
| GET | `/wallet` | {balance, ledger[], orders[]} |
| POST | `/wallet/orders` | {amount 10.000–5.000.000} → order{id,code,amount,status,qr_url,bank,account,account_name,is_live} |
| DELETE | `/wallet/orders/{id}` | huỷ đơn đang chờ → status 'cancelled' |
| GET | `/admin/overview` | users, tabs (có worker_id,user_id), orders (có user_id), jars (có user_id), workers[{id,capacity,used,online,draining,memory_mb,last_seen}], audit, stats{total_revenue,total_users_balance,total_tabs,active_tabs,pending_jars,users} |
| GET | `/admin/users/{id}` | chi tiết: user (tabs, running, jars, paid, sessions, last_login, note, max_tabs), tabs, slots, jars, orders, ledger, audit |
| PATCH | `/admin/users/{id}` | {name?, email?, role? user\|admin, max_tabs? 0–200, note?, blocked?, trial_approved?} — không khoá/hạ quyền chính mình hay admin cuối |
| DELETE | `/admin/users/{id}` | xoá tài khoản và toàn bộ tab/slot/JAR/đơn/lịch sử ví (xác nhận 2 bước trên UI) |
| POST | `/admin/users/{id}/password` | đặt lại mật khẩu → {password} tạm, hiện 1 lần; đăng xuất mọi thiết bị |
| POST | `/admin/users/{id}/logout` | buộc đăng xuất → {sessions} |
| DELETE | `/admin/tabs/{id}?release_slot=bool` | xoá tab cưỡng chế (mặc định giữ slot đã trả tiền) |
| DELETE | `/admin/jars/{id}` | xoá JAR; tab đang dùng chuyển về "Chưa chọn game" |
| POST | `/admin/orders/{id}/cancel` | huỷ đơn chờ |
| POST/DELETE | `/admin/workers`, `/admin/workers/{id}` | thêm {id,capacity} / xoá worker (409 nếu còn slot) |
| GET | `/admin/stats?days=30` | {days:[{date,topup,spend,signups,rentals}]} cho biểu đồ |
| GET | `/admin/audit?q=&limit=&offset=` | nhật ký có tìm kiếm, phân trang → {items, more} |
| GET | `/admin/export/{users\|orders\|ledger\|tabs}.csv` | xuất CSV (UTF-8 BOM, mở được bằng Excel) |
| GET | `/admin/jars/{id}/download` | admin tải file JAR về kiểm tra |
| PATCH | `/admin/jars/{id}` | {status:'approved'\|'rejected'} |
| PATCH | `/admin/workers/{id}` | {capacity, draining} |
| POST | `/admin/users/{id}/balance` | {amount (±), reason} — cộng/trừ ví có ghi lý do |
| POST | `/admin/orders/{id}/confirm` | {reference} — xác nhận tay đơn chuyển khoản sai nội dung |
| GET | `/admin/settings` | {site, support, plans[{id,name,days,price,badge,active}], topup_presets} |
| PUT | `/admin/settings/{site\|support\|plans\|topup_presets}` | lưu nội dung trang, liên hệ, bảng giá, mức nạp nhanh — có hiệu lực ngay cho web và app |
| POST | `/admin/tabs/{id}/extend` | {hours} — tặng/bù giờ |

Trạng thái đơn nạp: pending, paid, cancelled. Phiên đăng nhập 14 ngày.

Thời gian là Unix giây. Tiền là số nguyên VNĐ.

## Stream thời gian thực (WebSocket) — dùng cho màn xem game
`ws(s)://<host>/api/tabs/{id}/stream?fps=30|60`
- Xác thực: web dùng cookie (cùng origin); Godot gửi header `Authorization: Bearer <token>` khi bắt tay.
- Server → client:
  - tin **nhị phân** = một khung hình **JPEG** (J2ME theo `tab.screen`, ví dụ 240×320 / 320×240 / 640×360; Java PC 640×480). Hiển thị khung mới nhất, bỏ khung cũ.
  - tin **text JSON**: `{"type":"hello","kind":"midp"|"jar","width","height","fps"}` ngay khi kết nối;
    `{"type":"error","detail"}` khi thao tác sai.
- Client → server (text JSON), độ trễ ~150 ms:
  - `{"type":"key","key":"5"}` (cùng danh sách phím như `/input`)
  - `{"type":"text","text":"abc"}`
  - `{"type":"tap","x":120,"y":200}` hoặc thêm `"x2","y2"` để vuốt (toạ độ pixel của khung hình)
  - `{"type":"fps","fps":60}` đổi FPS không cần kết nối lại
  - `{"type":"ping","t":<số bất kỳ>}` → server trả `{"type":"pong","t":...}` để đo độ trễ
- Mã đóng: 4401 chưa đăng nhập, 4403 sai origin, 4404 không có tab, 4409 tab không chạy (hết hạn/đã dừng), 4429 quá nhiều người xem.
  Khi đóng bất thường: tự kết nối lại sau 1–2 giây; trong lúc chờ có thể dùng `GET /tabs/{id}/frame` (ảnh tĩnh).
- Khung đầu tiên tới sau ~1–2 giây (worker bật ffmpeg ở nhịp kế tiếp). Hiện bộ đếm FPS thực tế và nút chọn 30/60.
- Đa màn hình vẫn dùng `GET /tabs/{id}/frame` mỗi `poll_seconds.wall` giây (không mở nhiều stream).

## Tính năng tăng trưởng & hỗ trợ (backend/features.py)
| Method | Path | Ghi chú |
|---|---|---|
| GET | `/config` | thêm `referral{enabled,percent,max_bonus}`, `maintenance{enabled,message,until}` (bật → banner toàn hệ thống; người dùng thường không thuê/mua slot/tải JAR được, API trả 503 kèm message) |
| POST | `/auth/register` | thêm `ref` (mã giới thiệu, lấy từ `/#/register?ref=CODE`) |
| GET | `/me/referral` | {code, path, enabled, percent, max_bonus, invited, earned, friends[{name,created}]} — người được mời nạp lần đầu → người mời nhận `percent`% (tối đa max_bonus) |
| POST | `/coupons/check` | {code, context: rent\|topup, amount} → xem trước: rent {discount, final, message}, topup {bonus, message}; 422 kèm lý do |
| POST | `/tabs`, `/tabs/{id}/renew`, `/slots` | thêm `coupon` (mã giảm giá thuê) |
| POST | `/wallet/orders` | thêm `coupon` (mã thưởng nạp); order trả `coupon` |
| POST | `/tabs/{id}/restart` | khởi động lại game (tab trả `boot` tăng 1) |
| POST | `/tabs/batch` | {ids[≤50], action: start\|stop\|restart\|group, group?} → {done} |
| PATCH | `/tabs/{id}/schedule` | {group?, restart_at? "HH:MM" hoặc ""} — nhóm tab và giờ tự khởi động lại mỗi ngày; tab có `group`, `restart_at` |
| GET/POST | `/tabs/{id}/shares` | chia sẻ tab: {can_control, hours 1–720, label} → {token, path:"/#/s/TOKEN", expires, can_control}; tối đa 10 link |
| DELETE | `/tabs/{id}/shares/{token}` | thu hồi |
| GET | `/share/{token}` | công khai, không cần đăng nhập: {tab_id, name, status, desired, screen, can_control, expires, label} |
| WS | `/tabs/{tab_id}/stream?share=TOKEN&fps=` | xem qua link chia sẻ (không cookie); link chỉ xem → gửi phím nhận error "chỉ cho phép xem" |
| GET/POST | `/tickets` | hỗ trợ: {subject, body} tạo yêu cầu; list [{id,subject,status open\|answered\|closed,created,updated,messages_count}] |
| GET | `/tickets/{id}` | kèm messages[{id,staff,body,created}] |
| POST | `/tickets/{id}/messages`, `/tickets/{id}/close` | trả lời / đóng (admin trả lời → status answered + thông báo cho người dùng) |
| GET | `/notifications` | {unread, items[{id,title,body,link,read,created}]} — link là route web (ví dụ "/wallet", "/tabs/ID", "/support/ID") |
| POST | `/notifications/read` | {ids[]} hoặc {all:true} |
| GET | `/me/sessions` | thiết bị đăng nhập [{id,agent,created,expires,current}] |
| DELETE | `/me/sessions/{id}` | đăng xuất thiết bị đó |
| GET/POST/PUT/DELETE | `/admin/coupons`, `/admin/coupons/{code}` | {code, kind percent\|amount\|topup, value, max_value, min_amount, max_uses(0=∞), per_user, expires(0=∞), active, note}; GET trả {coupons, uses} |
| GET | `/admin/tickets?status=` | kèm email người gửi; trả lời qua `/tickets/{id}/messages` |
| POST | `/admin/notifications` | {title, body, link, user_id?} gửi một người hoặc tất cả → {sent} |
| GET | `/admin/growth` | {referral, maintenance, top_referrers[{user_id,email,invited}], open_tickets} |
| PUT | `/admin/settings/referral` · `/admin/settings/maintenance` | {enabled, percent 0–50, max_bonus, referee_bonus} · {enabled, message, until} |

Thông báo tự động: nạp tiền thành công, thưởng giới thiệu, tab sắp hết hạn (theo `prefs.expiry_alert_hours`, một lần mỗi kỳ hạn), tự gia hạn thành công/thất bại, admin tặng giờ, hỗ trợ trả lời.
