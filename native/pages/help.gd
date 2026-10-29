extends "res://native/pages/page.gd"
## "Hướng dẫn": how to use the service, key mapping and real support contacts.


func build() -> void:
	var cfg: Dictionary = app.config
	var steps := UI.card(self, "Card", T.space("md"))
	UI.label(steps, "Bắt đầu nhanh", "SubheadingLabel")
	var items := [
		["Nạp tiền vào ví", ("Vào mục Ví, tạo đơn nạp và chuyển khoản đúng nội dung." + (" Tiền tự cộng sau 5–30 giây." if cfg.get("auto_topup", false) else "")) if cfg.get("payment_ready", false) else "Nạp tiền đang tạm ngưng, vui lòng quay lại sau."],
		["Thuê tab", "Ở mục Tab của tôi, bấm \"+ Thuê tab mới\", chọn game khởi đầu và gói thời gian. Muốn chơi game khác? Bấm \"Đổi game\" trên tab bất cứ lúc nào."],
		["Dùng game của bạn", "Tải file .jar (J2ME cho điện thoại Nokia hoặc Java PC) ở mục File JAR, rồi chọn nó trong \"Đổi game\"."],
		["Mở màn hình", "Bấm \"Mở màn hình\" để xem game trực tiếp và điều khiển bằng bàn phím ảo hoặc bàn phím máy tính."],
		["Để tab tự chạy", "Đóng ứng dụng thoải mái — tab vẫn chạy 24/24 cho tới khi hết hạn."],
	]
	if bool(app.user.get("trial_approved", 0)) and not bool(app.user.get("trial_used", 0)):
		items.insert(1, ["Dùng thử miễn phí", "Tài khoản của bạn được dùng thử %d phút — chọn ô \"Dùng thử\" khi thuê tab." % int(cfg.get("trial_minutes", 0))])
	for i in items.size():
		var row := UI.hbox(steps, T.space("md"))
		var num := UI.badge(row, str(i + 1), T.color("accent"))
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var text := UI.vbox(row, 2)
		UI.label(text, items[i][0], "StrongLabel")
		UI.label(text, items[i][1], "MutedLabel")

	var keys := UI.card(self, "Card", T.space("sm"))
	UI.label(keys, "Phím điều khiển", "SubheadingLabel")
	for k in [["Mũi tên", "Di chuyển (▲ ▼ ◀ ▶)"], ["Enter", "OK / chọn"], ["F1 / F2", "Phím mềm trái / phải"], ["0 – 9, * , #", "Phím số Nokia"], ["Backspace", "Xóa"], ["Esc / Space", "Thoát / phím cách"], ["Gửi chữ", "Gõ tài khoản, mật khẩu (chữ không dấu)"]]:
		var row := UI.hbox(keys, T.space("md"))
		var a := UI.label(row, k[0], "MonoLabel", false)
		a.custom_minimum_size.x = 130
		UI.label(row, k[1], "", true)

	var facts := UI.card(self, "Card", T.space("sm"))
	UI.label(facts, "Thông số tab", "SubheadingLabel")
	UI.label(facts, "Mỗi tab chạy trong môi trường riêng, an toàn. Tối đa %d tab mỗi tài khoản; file game tối đa %d MB." % [int(cfg.get("max_tabs", 20)), int(cfg.get("jar_max_mb", 30))], "BodyMutedLabel")
	UI.label(facts, "Trạng thái tab: " + ", ".join(PackedStringArray(["running", "queued", "stopped", "expired", "error"].map(func(s: String) -> String: return T.status_label(s)))) + ".", "MutedLabel")

	var support := UI.card(self, "Card", T.space("sm"))
	UI.label(support, "Hỗ trợ", "SubheadingLabel")
	var names := {"zalo": "Zalo", "telegram": "Telegram", "email": "Email"}
	var any := false
	for k in names:
		var v := str(cfg.get("support", {}).get(k, "")).strip_edges()
		if v.is_empty():
			continue
		any = true
		var row := UI.hbox(support, T.space("md"))
		var n := UI.label(row, names[k], "MutedLabel", false)
		n.custom_minimum_size.x = 90
		UI.label(row, v, "StrongLabel")
		UI.button(row, "Sao chép", func() -> void:
			DisplayServer.clipboard_set(v)
			app.toast("Đã sao chép."), "GhostButton")
	if not any:
		UI.label(support, "Chưa có kênh hỗ trợ nào được cấu hình.", "MutedLabel")
