extends RefCounted
## Tab/slot actions and their dialogs, shared by the Tabs, Viewer, Wall, Plans, JAR and Admin pages.
## Static so a dialog never depends on the lifetime of the page that opened it.

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")
const Api := preload("res://native/api.gd")


static func can_release(tab: Dictionary) -> bool:
	return str(tab.get("desired")) == "stopped" and str(tab.get("status")) in ["stopped", "expired", "error"]


static func is_expired(tab: Dictionary) -> bool:
	return int(tab.get("expires", 0)) <= UI.now()


static func toggle(app: Node, tab: Dictionary) -> void:
	var start := str(tab.get("desired")) != "running"
	await app.act("/tabs/" + str(tab.id), Api.PATCH, {"desired": "running" if start else "stopped"},
		("Đã gửi lệnh chạy: %s" if start else "Đã gửi lệnh dừng: %s") % str(tab.name))


static func restart(app: Node, tab: Dictionary) -> void:
	await app.act("/tabs/%s/restart" % str(tab.id), Api.POST, null, "Đang khởi động lại %s…" % str(tab.name))


## Batch action on selected tabs (POST /tabs/batch): start | stop | restart | group.
static func batch_ids(app: Node, ids: Array, action: String, group: String = "") -> Dictionary:
	var body := {"ids": ids.slice(0, 50), "action": action}
	if action == "group":
		body["group"] = group
	var labels := {"start": "chạy", "stop": "dừng", "restart": "khởi động lại", "group": "chuyển nhóm"}
	var r: Dictionary = await app.api.request("/tabs/batch", Api.POST, body)
	if r.ok:
		app.toast("Đã %s %d tab." % [labels.get(action, action), int(r.data.get("done", 0))])
	else:
		app.toast(r.error, true)
	await app.refresh(true)
	return r


static func groups(app: Node) -> Array:
	var out: Array = []
	for t in app.tabs:
		var g := str(t.get("group", "")).strip_edges()
		if not g.is_empty() and not g in out:
			out.append(g)
	out.sort()
	return out


## "Nhóm…": pick an existing group, type a new one, or remove from groups. ids = several tabs (batch).
static func group_dialog(app: Node, tab: Dictionary, ids: Array = []) -> void:
	var many := not ids.is_empty()
	var body: VBoxContainer = app.open_modal("Chuyển %d tab vào nhóm" % ids.size() if many else "Nhóm: %s" % str(tab.get("name", "")), 440)
	var input := UI.field(body, "Tên nhóm", "Ví dụ: Nick phụ, Cày đêm…")
	input.max_length = 40
	input.text = "" if many else str(tab.get("group", ""))
	var existing := groups(app)
	if not existing.is_empty():
		UI.label(body, "Nhóm hiện có", "MutedLabel")
		var row := UI.flow(body, T.space("xs") + 2)
		for g in existing:
			UI.button(row, g, func() -> void: input.text = g, "ChipButton").custom_minimum_size.y = UI.target_h(32)
	var save := func(name: String) -> void:
		var r: Dictionary
		if many:
			r = await batch_ids(app, ids, "group", name)
		else:
			r = await app.act("/tabs/%s/schedule" % str(tab.id), Api.PATCH, {"group": name}, "Đã chuyển vào nhóm \"%s\"." % name if not name.is_empty() else "Đã bỏ khỏi nhóm.")
		if r.ok:
			app.close_modal()
	var foot: HBoxContainer = app.modal_footer()
	UI.button(foot, "Bỏ nhóm", func() -> void: save.call(""), "GhostButton")
	UI.button(foot, "Lưu", func() -> void: save.call(input.text.strip_edges()), "PrimaryButton")
	input.text_submitted.connect(func(t: String) -> void: save.call(t.strip_edges()))


## "Hẹn giờ khởi động lại": daily HH:MM or off (PATCH /tabs/{id}/schedule {restart_at}).
static func schedule_dialog(app: Node, tab: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Hẹn giờ khởi động lại", 440)
	UI.label(body, "Tab \"%s\" sẽ tự khởi động lại game mỗi ngày vào giờ đã chọn (giờ Việt Nam). Hữu ích cho game hay treo hoặc rò rỉ bộ nhớ." % str(tab.get("name", "")), "BodyMutedLabel")
	var input := UI.field(body, "Giờ (HH:MM)", "04:00")
	input.max_length = 5
	input.text = str(tab.get("restart_at", ""))
	var quick := UI.flow(body, T.space("xs") + 2)
	for h in ["00:00", "04:00", "06:00", "12:00", "18:00"]:
		UI.button(quick, h, func() -> void: input.text = h, "ChipButton").custom_minimum_size.y = UI.target_h(32)
	var send := func(value: String) -> void:
		if not value.is_empty():
			var ok := value.length() == 5 and value[2] == ":" and value.left(2).is_valid_int() and value.right(2).is_valid_int() \
				and int(value.left(2)) < 24 and int(value.right(2)) < 60
			if not ok:
				app.toast("Nhập giờ dạng HH:MM, ví dụ 04:30.", true)
				return
		var r: Dictionary = await app.act("/tabs/%s/schedule" % str(tab.id), Api.PATCH, {"restart_at": value},
			("Sẽ khởi động lại lúc %s mỗi ngày." % value) if not value.is_empty() else "Đã tắt hẹn giờ.")
		if r.ok:
			app.close_modal()
	var foot: HBoxContainer = app.modal_footer()
	if not str(tab.get("restart_at", "")).is_empty():
		UI.button(foot, "Tắt hẹn giờ", func() -> void: send.call(""), "GhostButton")
	UI.button(foot, "Lưu", func() -> void: send.call(input.text.strip_edges()), "PrimaryButton")


## "Chia sẻ": view-only or control links with an expiry (web link <web origin>/#/s/TOKEN).
static func share_dialog(app: Node, tab: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Chia sẻ: %s" % str(tab.get("name", "")), 560)
	UI.label(body, "Người nhận mở liên kết trên trình duyệt, không cần đăng nhập. Thu hồi bất cứ lúc nào.", "BodyMutedLabel")
	var form := UI.card(body, "CardInset", T.space("sm"))
	var mode := UI.option(form, "Quyền")
	mode.add_item("Chỉ xem màn hình")
	mode.add_item("Xem và điều khiển")
	var dur := UI.option(form, "Thời hạn")
	var hours := [1, 24, 168, 720]
	for h in ["1 giờ", "24 giờ", "7 ngày", "30 ngày"]:
		dur.add_item(h)
	dur.selected = 1
	var label := UI.field(form, "Ghi chú (không bắt buộc)", "Ví dụ: Gửi bạn A")
	label.max_length = 40
	var list := UI.vbox(body, T.space("sm"))
	var origin: String = app.web_url()
	var render := func(items: Array) -> void:
		UI.clear(list)
		UI.label(list, "Liên kết đang hoạt động (%d/10)" % items.size(), "StrongLabel")
		if items.is_empty():
			UI.label(list, "Chưa có liên kết nào.", "MutedLabel")
		for sh in items:
			var url := origin + str(sh.get("path", "/#/s/" + str(sh.token)))
			var row := UI.card(list, "CardInset", T.space("xs"))
			var top := UI.hbox(row, T.space("sm"))
			UI.label_clip(top, str(sh.get("label", "")) if str(sh.get("label", "")) != "" else "Liên kết chia sẻ", "StrongLabel")
			UI.badge(top, "Điều khiển" if sh.get("can_control", false) else "Chỉ xem", T.color("warn") if sh.get("can_control", false) else T.color("info"))
			UI.label_clip(row, "Hết hạn %s" % UI.datetime(sh.get("expires")), "DimLabel")
			var acts := UI.flow(row, T.space("sm"))  # wraps on phones (3 buttons)
			acts.alignment = FlowContainer.ALIGNMENT_END
			UI.button(acts, "Sao chép liên kết", func() -> void:
				DisplayServer.clipboard_set(url)
				app.toast("Đã sao chép liên kết."), "")
			var tok := str(sh.token)
			# QR (PNG made by the server, same web link): opens under the link; tap again to hide.
			UI.button(acts, "Mã QR", func() -> void:
				if row.has_meta("qr"):
					var box: Control = row.get_meta("qr")
					box.visible = not box.visible
					return
				var q: Dictionary = await app.api.fetch_bytes("/tabs/%s/shares/%s/qr" % [str(tab.id), tok])
				if not is_instance_valid(row):
					return
				var img := UI.decode_image(q.data) if q.ok else null
				if img == null:
					app.toast(str(q.get("error", "")) if str(q.get("error", "")) != "" else "Không tải được mã QR.", true)
					return
				var box := UI.vbox(row, T.space("xs"))
				var center := CenterContainer.new()
				box.add_child(center)
				var tex := TextureRect.new()
				tex.texture = ImageTexture.create_from_image(img)
				tex.custom_minimum_size = Vector2(220, 220)
				tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp modules
				center.add_child(tex)
				var hint := UI.label(box, "Quét bằng camera điện thoại để mở liên kết.", "DimLabel")
				hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				if not OS.has_feature("mobile"):
					var save_row := CenterContainer.new()
					box.add_child(save_row)
					UI.button(save_row, "Lưu ảnh QR", func() -> void:
						var path := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join("thuetab-qr-%s.png" % tok.left(8))
						if img.save_png(path) == OK:
							app.toast("Đã lưu " + path)
						else:
							app.toast("Không lưu được ảnh QR.", true), "GhostButton")
				row.set_meta("qr", box), "")
			UI.button(acts, "Thu hồi", func() -> void:
				var r: Dictionary = await app.api.request("/tabs/%s/shares/%s" % [str(tab.id), tok], Api.DELETE)
				if r.ok:
					app.toast("Đã thu hồi liên kết.")
					share_dialog(app, tab)
				else:
					app.toast(r.error, true), "DangerButton")
	var foot: HBoxContainer = app.modal_footer()
	UI.button(foot, "Đóng", app.close_modal, "GhostButton")
	var create := UI.button(foot, "Tạo liên kết", Callable(), "PrimaryButton")
	UI.on_press(create, func() -> void:
		create.disabled = true
		var r: Dictionary = await app.api.request("/tabs/%s/shares" % str(tab.id), Api.POST,
			{"can_control": mode.selected == 1, "hours": hours[dur.selected], "label": label.text.strip_edges()})
		if r.ok:
			var url := origin + str(r.data.get("path", ""))
			DisplayServer.clipboard_set(url)
			app.toast("Đã tạo và sao chép liên kết.")
			share_dialog(app, tab)
		else:
			app.toast(r.error, true)
			if is_instance_valid(create):
				create.disabled = false)
	var r0: Dictionary = await app.api.request("/tabs/%s/shares" % str(tab.id))
	if is_instance_valid(list) and list.is_inside_tree():
		if r0.ok:
			render.call(r0.data if r0.data is Array else [])
		else:
			UI.label(list, r0.error, "DangerLabel")


## "Mã khuyến mãi" field with "Áp dụng" (POST /coupons/check). context: rent | topup.
## amount_fn() returns the current amount; on_change() is called when the result changes.
## Returns a state Dictionary {code, discount, bonus, message} — code is "" when nothing valid is applied.
static func coupon_box(app: Node, parent: Node, context: String, amount_fn: Callable, on_change: Callable = Callable(), state: Dictionary = {}) -> Dictionary:
	# Filled in place so callers' lambdas (which capture the dictionary reference) see updates.
	state.merge({"code": "", "discount": 0, "bonus": 0, "message": "", "checked_for": -1}, true)
	var box := UI.vbox(parent, T.space("xs") + 2)
	UI.label(box, "Mã khuyến mãi", "MutedLabel")
	var row := UI.hbox(box, T.space("sm"))
	var input := LineEdit.new()
	input.placeholder_text = "Nhập mã (không bắt buộc)"
	input.max_length = 32
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = UI.target_h(40)
	row.add_child(input)
	var apply := UI.button(row, "Áp dụng", Callable(), "")
	var msg := UI.label(box, "", "MutedLabel")
	msg.visible = false
	var check := func() -> void:
		var code := input.text.strip_edges().to_upper()
		if code.is_empty():
			state.code = ""
			state.discount = 0
			state.bonus = 0
			msg.visible = false
			if on_change.is_valid():
				on_change.call()
			return
		apply.disabled = true
		var amount := int(amount_fn.call())
		var r: Dictionary = await app.api.request("/coupons/check", Api.POST, {"code": code, "context": context, "amount": amount})
		if not is_instance_valid(apply):
			return
		apply.disabled = false
		msg.visible = true
		if r.ok:
			state.code = str(r.data.get("code", code))
			state.discount = int(r.data.get("discount", 0))
			state.bonus = int(r.data.get("bonus", 0))
			state.checked_for = amount
			msg.text = "✓ " + str(r.data.get("message", "Đã áp dụng mã."))
			msg.add_theme_color_override("font_color", T.color("success"))
		else:
			state.code = ""
			state.discount = 0
			state.bonus = 0
			msg.text = r.error
			msg.add_theme_color_override("font_color", T.color("danger"))
		if on_change.is_valid():
			on_change.call()
	apply.pressed.connect(check)
	input.text_submitted.connect(func(_t: String) -> void: check.call())
	input.text_changed.connect(func(_t: String) -> void:
		if not str(state.code).is_empty():
			state.code = ""
			state.discount = 0
			state.bonus = 0
			msg.visible = false
			if on_change.is_valid():
				on_change.call())
	state["recheck"] = check  # call when the amount changes (e.g. another plan)
	return state


static func batch(app: Node, desired: String) -> void:
	var n := 0
	for t in app.tabs:
		if str(t.desired) != desired and not is_expired(t):
			var r: Dictionary = await app.api.request("/tabs/" + str(t.id), Api.PATCH, {"desired": desired})
			if r.ok:
				n += 1
	if n == 0:
		app.toast("Không có tab nào cần thay đổi.")
	else:
		app.toast(("Đã gửi lệnh chạy %d tab." if desired == "running" else "Đã gửi lệnh dừng %d tab.") % n)
	await app.refresh(true)


static func set_auto_renew(app: Node, tab: Dictionary, on: bool) -> void:
	await app.act("/tabs/" + str(tab.id), Api.PATCH, {"auto_renew": on},
		"Đã bật tự động gia hạn." if on else "Đã tắt tự động gia hạn.")


static func release(app: Node, tab: Dictionary) -> void:
	app.confirm("Giải phóng tab", "Xóa tab \"%s\" khỏi tài khoản? Slot đã trả tiền (nếu còn hạn) vẫn được giữ để gắn tab khác." % str(tab.name),
		"Giải phóng", func() -> void:
			await app.act("/tabs/" + str(tab.id), Api.DELETE, null, "Đã giải phóng tab."), true)


## Warning strip when a tab expires within 24 h, with a quick renew action.
static func expiry_warning(app: Node, parent: Node, tab: Dictionary) -> void:
	var left := int(tab.get("expires", 0)) - UI.now()
	if left <= 0 or left >= 86400:
		return
	var p := PanelContainer.new()
	var c := T.color("warn")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c, 0.12)
	sb.border_color = Color(c, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(T.radius("md"))
	sb.content_margin_left = T.space("md")
	sb.content_margin_right = T.space("xs")
	sb.content_margin_top = T.space("xs")
	sb.content_margin_bottom = T.space("xs")
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var row := UI.hbox(p, T.space("sm"))
	var text := "Sắp hết hạn — %s" % UI.time_left(tab.expires).to_lower()
	if tab.get("auto_renew", false):
		text += " (sẽ tự gia hạn)"
	var l := UI.label(row, text, "")
	l.add_theme_color_override("font_color", c.lightened(0.15))
	l.add_theme_font_size_override("font_size", T.font_size("sm"))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b := UI.button(row, "Gia hạn", func() -> void: renew(app, tab, false), "GhostButton")
	b.custom_minimum_size.y = UI.target_h(30)


static func rename(app: Node, tab: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Đổi tên tab", 420)
	var input := UI.field(body, "Tên mới", "Tên tab")
	input.text = str(tab.name)
	input.max_length = 60
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var save := func() -> void:
		var r: Dictionary = await app.act("/tabs/" + str(tab.id), Api.PATCH, {"name": input.text.strip_edges()}, "Đã đổi tên tab.")
		if r.ok:
			app.close_modal()
	UI.button(row, "Lưu", save, "PrimaryButton")
	input.text_submitted.connect(func(_t: String) -> void: save.call())
	input.grab_focus.call_deferred()


## Rename a JAR: only the name, the ".jar" extension is fixed (shown after the field).
static func rename_jar(app: Node, jar: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Đổi tên file JAR", 420)
	var input := UI.field(body, "Tên mới", "Tên dễ nhớ")
	var box := input.get_parent()
	var line := UI.hbox(box, T.space("sm"))
	input.reparent(line)
	UI.label(line, ".jar", "MutedLabel", false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input.text = str(jar.filename).trim_suffix(".jar").trim_suffix(".JAR")
	input.max_length = 115
	UI.label(body, "Chỉ đổi tên cho dễ nhớ; file game và đuôi .jar giữ nguyên.", "MutedLabel")
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var save := func() -> void:
		var stem := input.text.strip_edges()
		if stem.is_empty():
			app.toast("Tên file không được để trống.", true)
			return
		var r: Dictionary = await app.act("/jars/" + str(jar.id), Api.PATCH, {"filename": stem + ".jar"}, "Đã đổi tên file.")
		if r.ok:
			app.close_modal()
	UI.button(row, "Lưu", save, "PrimaryButton")
	input.text_submitted.connect(func(_t: String) -> void: save.call())
	input.grab_focus.call_deferred()


## Renew a tab (is_slot=false) or a slot (is_slot=true) with one of config.plans.
static func renew(app: Node, item: Dictionary, is_slot: bool) -> void:
	var title := "Gia hạn slot" if is_slot else "Gia hạn: %s" % str(item.get("name", ""))
	var body: VBoxContainer = app.open_modal(title, 480)
	UI.label(body, "Hạn hiện tại: %s (%s). Thời gian mới được cộng tiếp vào hạn hiện tại." % [UI.datetime(item.get("expires")), UI.time_left(item.get("expires")).to_lower()], "BodyMutedLabel")
	var plans: Array = app.config.get("plans", [])
	var opt := UI.option(body, "Gói gia hạn")
	for p in plans:
		opt.add_item("%s · %d ngày · %s" % [str(p.name), int(p.days), UI.money(p.price)])
	opt.selected = 0 if not plans.is_empty() else -1
	var summary := UI.card(body, "CardInset", T.space("xs"))
	var foot: HBoxContainer = app.modal_footer()
	UI.button(foot, "Hủy", app.close_modal, "GhostButton")
	var go_btn := UI.button(foot, "Gia hạn", Callable(), "PrimaryButton")
	var coupon := {}
	var update := func() -> void:
		if plans.is_empty() or opt.selected < 0:
			return
		var price := int(plans[opt.selected].price)
		var final_price := maxi(0, price - int(coupon.get("discount", 0))) if not str(coupon.get("code", "")).is_empty() else price
		UI.clear(summary)
		var line := UI.hbox(summary, T.space("sm"))
		UI.label(line, "Thanh toán", "BodyMutedLabel")
		UI.label(line, UI.money(final_price), "SubheadingLabel", false)
		UI.label(summary, "Số dư hiện tại: %s" % UI.money(app.user.get("balance", 0)), "MutedLabel")
		var short := final_price > int(app.user.get("balance", 0))
		if short:
			UI.label(summary, "Số dư không đủ — hãy nạp thêm %s." % UI.money(final_price - int(app.user.get("balance", 0))), "DangerLabel")
		go_btn.disabled = short
	coupon_box(app, body, "rent", func() -> int: return int(plans[maxi(opt.selected, 0)].price) if not plans.is_empty() else 0, update, coupon)
	opt.item_selected.connect(func(_i: int) -> void:
		if not str(coupon.code).is_empty():
			coupon.recheck.call()
		update.call())
	go_btn.pressed.connect(func() -> void:
		var data := {"plan": str(plans[opt.selected].id)}
		if not str(coupon.code).is_empty():
			data["coupon"] = coupon.code
		var path := ("/slots/%s/renew" if is_slot else "/tabs/%s/renew") % str(item.id)
		go_btn.disabled = true
		var r: Dictionary = await app.act(path, Api.POST, data, "Gia hạn thành công.")
		if r.ok:
			app.close_modal()
		elif is_instance_valid(go_btn):
			go_btn.disabled = false)
	update.call()


static func logs(app: Node, tab: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Nhật ký: %s" % str(tab.name), 760)
	var info := UI.label(body, "Các dòng gần nhất do game in ra.", "MutedLabel")
	var box := TextEdit.new()
	box.editable = false
	box.custom_minimum_size = Vector2(0, 340)
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.text = "Đang tải nhật ký…"
	body.add_child(box)
	var row: HBoxContainer = app.modal_footer()
	var load_logs := func() -> void:
		box.text = "Đang tải nhật ký…"
		var r: Dictionary = await app.api.request("/tabs/%s/logs" % str(tab.id))
		if not is_instance_valid(box):
			return
		box.text = str(r.data.get("logs", "")) if r.ok else "Lỗi: " + r.error
		if r.ok and r.data.get("updated") != null:
			info.text = "Các dòng gần nhất do game in ra · cập nhật %s" % UI.datetime(r.data.updated)
		box.scroll_vertical = box.get_line_count()
	UI.button(row, "Sao chép", func() -> void:
		DisplayServer.clipboard_set(box.text)
		app.toast("Đã sao chép nhật ký."), "GhostButton")
	UI.button(row, "Làm mới", load_logs, "")
	# The worker uploads logs only while they are being requested: refresh every 5 s while open.
	var timer := Timer.new()
	timer.wait_time = 5.0
	body.add_child(timer)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(box) and body.is_inside_tree():
			var r: Dictionary = await app.api.request("/tabs/%s/logs" % str(tab.id))
			if r.ok and is_instance_valid(box):
				var at_end := box.scroll_vertical >= box.get_line_count() - box.get_visible_line_count() - 1
				box.text = str(r.data.get("logs", ""))
				if at_end:
					box.scroll_vertical = box.get_line_count())
	timer.start()
	await load_logs.call()


# ---------------------------------------------------------------- JAR upload

## Opens the native file dialog, uploads the chosen .jar, refreshes app.jars and calls on_done(jar_dict).
static func pick_and_upload(app: Node, on_done: Callable = Callable()) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "Chọn file .jar"
	# Android's picker only offers files whose MIME type is listed: JARs are often x-java-archive or octet-stream.
	fd.filters = PackedStringArray(["*.jar;Java Archive;application/java-archive,application/x-java-archive,application/octet-stream"])
	app.add_child(fd)
	fd.file_selected.connect(func(path: String) -> void:
		fd.queue_free()
		var jar: Dictionary = await upload(app, path)
		if not jar.is_empty() and on_done.is_valid():
			on_done.call(jar))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.7)


## File name to show and send: Android pickers give "content://…/document/primary%3ADownload%2Fgame.jar",
## so the URI is decoded and only the last path part is kept.
static func file_name(path: String) -> String:
	var name := path
	for i in 3:
		if not name.contains("%"):
			break
		name = name.uri_decode()
	name = name.get_file()
	return name.get_slice(":", name.get_slice_count(":") - 1)


static func upload(app: Node, path: String) -> Dictionary:
	var max_mb := int(app.config.get("jar_max_mb", 30))
	var name := file_name(path)
	# content:// documents may have no ".jar" in the name at all; the server checks the file itself.
	if not path.begins_with("content://") and not name.to_lower().ends_with(".jar"):
		app.toast("Chỉ chấp nhận file .jar.", true)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		app.toast("Không mở được file: " + name, true)
		return {}
	if f.get_length() > max_mb * 1048576:
		app.toast("File vượt quá %d MB." % max_mb, true)
		return {}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	app.toast("Đang tải lên %s (%s)…" % [name, UI.file_size(bytes.size())])
	var r: Dictionary = await app.api.request_raw("/jars/upload", Api.POST, bytes, PackedStringArray([
		"Content-Type: application/octet-stream",
		"X-Filename: " + name.uri_encode(),
	]))
	if not r.ok:
		app.toast(r.error, true)
		return {}
	var jar: Dictionary = r.data.get("jar", {})
	var st := str(jar.get("status", "approved"))
	app.toast("Đã tải lên %s (%s)." % [str(jar.get("filename", name)), kind_label(str(jar.get("kind", "")))] + ("" if st == "approved" else " Đang chờ duyệt."))
	var rj: Dictionary = await app.api.request("/jars")
	if rj.ok:
		app.jars = rj.data
	app.refresh(true)
	return jar


static func kind_label(kind: String) -> String:
	return "J2ME" if kind == "midp" else ("Java PC" if kind == "jar" else "JAR")


static func kind_badge(parent: Node, kind: String) -> PanelContainer:
	return UI.badge(parent, kind_label(kind), T.color("info") if kind == "midp" else T.color("muted"))


# ---------------------------------------------------------------- game picker

static func _overlay_row(b: Button) -> HBoxContainer:
	var row := UI.hbox(b, T.space("md"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = T.space("md")
	row.offset_right = -T.space("md")
	return row


## Renders the choice list (catalog games + the user's JARs + inline upload) into `box`.
## state = {game, jar}; on_change() is called after the selection changes.
static func game_picker(app: Node, box: VBoxContainer, state: Dictionary, on_change: Callable, allow_none: bool = false) -> void:
	UI.clear(box)
	var items: Array = []
	if allow_none:
		items.append({"game": "", "jar": "", "title": "Chọn game sau", "sub": "Thuê trước, chọn game bất cứ lúc nào",
			"icon": "custom", "enabled": true, "badge": "", "kind": ""})
	for g in app.config.get("games", []):
		if str(g.id) == "custom-jar" or not g.get("enabled", true):
			continue
		items.append({"game": str(g.id), "jar": "", "title": str(g.name), "sub": str(g.get("kind", "")) if g.get("enabled", false) else str(g.get("note", "")),
			"icon": str(g.get("icon", "")), "enabled": bool(g.get("enabled", false)), "badge": "" if g.get("enabled", false) else "Sắp có", "kind": ""})
	var custom: Dictionary = app.game("custom-jar")
	if custom.get("enabled", false):
		for j in app.jars:
			var st := str(j.get("status", "approved"))
			items.append({"game": "custom-jar", "jar": str(j.id), "title": str(j.filename),
				"sub": "%s · %s" % [UI.file_size(j.get("file_size", 0)), "File của bạn" if st == "approved" else T.jar_label(st)],
				"icon": "custom", "enabled": st == "approved", "badge": "", "kind": str(j.get("kind", ""))})
	var grid := GridContainer.new()
	grid.columns = 1 if app.compact else 2
	grid.add_theme_constant_override("h_separation", T.space("sm"))
	grid.add_theme_constant_override("v_separation", T.space("sm"))
	box.add_child(grid)
	var buttons: Array = []
	for it in items:
		var b := UI.button(grid, "", Callable(), "ChipButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 60
		b.disabled = not it.enabled
		b.set_meta("key", [it.game, it.jar])
		buttons.append(b)
		var row := _overlay_row(b)
		var icon := UI.image(row, UI.game_icon(it.icon), Vector2(36, 36))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := UI.vbox(row, 0)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var n := UI.label_clip(text, it.title, "StrongLabel")
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := UI.label_clip(text, it.sub, "MutedLabel" if it.enabled else "DimLabel")
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not it.enabled:
			icon.modulate.a = 0.4
			n.modulate.a = 0.55
		if it.kind != "":
			kind_badge(row, it.kind).mouse_filter = Control.MOUSE_FILTER_IGNORE
		elif it.badge != "":
			UI.badge(row, it.badge, T.color("dim")).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key: Array = [it.game, it.jar]
		b.pressed.connect(func() -> void:
			state.game = key[0]
			state.jar = key[1]
			for other in buttons:
				other.theme_type_variation = "ChipButtonActive" if other.get_meta("key") == key else "ChipButton"
			on_change.call())
		if [state.get("game", ""), state.get("jar", "")] == key:
			b.theme_type_variation = "ChipButtonActive"
	if custom.get("enabled", false):
		var row := UI.vbox(box, T.space("xs"))
		var up := UI.button(row, "+ Tải JAR mới", Callable(), "")
		up.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		up.pressed.connect(func() -> void:
			pick_and_upload(app, func(jar: Dictionary) -> void:
				if not is_instance_valid(box) or not box.is_inside_tree():
					return
				if str(jar.get("status", "")) == "approved":
					state.game = "custom-jar"
					state.jar = str(jar.id)
				game_picker(app, box, state, on_change, allow_none)
				on_change.call()))
		var hint := "File .jar J2ME (Nokia) hoặc Java PC, tối đa %d MB." % int(app.config.get("jar_max_mb", 30))
		if app.jars.is_empty():
			hint = "Bạn chưa có file game nào. " + hint
		if not bool(app.config.get("jar_auto_approve", true)):
			hint += " File mới cần quản trị viên duyệt."
		UI.label(row, hint, "DimLabel")


static func _refresh_lists(app: Node, slots: bool) -> void:
	if slots:
		var rs: Dictionary = await app.api.request("/slots")
		if rs.ok:
			app.slots = rs.data
	var rj: Dictionary = await app.api.request("/jars")
	if rj.ok:
		app.jars = rj.data


## "Đổi game": switch a tab to another catalog game or one of the user's JARs. The tab restarts.
static func change_game(app: Node, tab: Dictionary) -> void:
	var no_game: bool = tab.get("game") == null or str(tab.get("game", "")) == ""
	var body: VBoxContainer = app.open_modal(("Chọn game: %s" if no_game else "Đổi game: %s") % str(tab.name), 640)
	var loading := UI.label(body, "Đang tải danh sách…", "MutedLabel")
	await _refresh_lists(app, false)
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	loading.queue_free()
	UI.label(body, "Chọn file game cho tab. Tab giữ nguyên hạn dùng và tự khởi động lại với game mới.", "BodyMutedLabel")
	var state := {"game": str(tab.get("game", "")) if tab.get("game") != null else "", "jar": str(tab.get("custom_jar_id", "")) if tab.get("custom_jar_id") != null else ""}
	var current := state.duplicate()
	var picker := UI.vbox(body, T.space("sm"))
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var save := UI.button(row, "Chạy game này" if no_game else "Đổi game", Callable(), "PrimaryButton")
	var update := func() -> void:
		save.disabled = state.game == "" or (state.game == "custom-jar" and state.jar == "") or (state.game == current.game and state.jar == current.jar)
	game_picker(app, picker, state, update)
	update.call()
	UI.on_press(save, func() -> void:
		var data := {"game": state.game}
		if state.game == "custom-jar":
			data["custom_jar_id"] = state.jar
		save.disabled = true
		var r: Dictionary = await app.act("/tabs/" + str(tab.id), Api.PATCH, data, "Đã đổi game — tab đang khởi động lại.")
		if r.ok:
			app.close_modal()
		elif is_instance_valid(save):
			update.call())


# ---------------------------------------------------------------- rent

## Rent dialog. `preset_jar` preselects that JAR as the starting game.
static func rent(app: Node, preset_jar: String = "") -> void:
	var body: VBoxContainer = app.open_modal("Thuê tab mới", 640)
	var loading := UI.label(body, "Đang tải…", "MutedLabel")
	await _refresh_lists(app, true)
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	loading.queue_free()

	var state := {"game": "", "jar": ""}
	if not preset_jar.is_empty():
		state = {"game": "custom-jar", "jar": preset_jar}
	var name_input := UI.field(body, "Tên tab", "Ví dụ: Nick chính")
	name_input.max_length = 60
	var pick_head := UI.vbox(body, 2)
	UI.label(pick_head, "Game (không bắt buộc)", "MutedLabel")
	UI.label(pick_head, "Có thể chọn hoặc đổi game bất cứ lúc nào sau khi thuê.", "DimLabel")
	var picker := UI.vbox(body, T.space("sm"))
	var plan_box := UI.vbox(body, T.space("md"))
	var coupon_slot := UI.vbox(body, 0)
	var summary := UI.card(body, "CardInset", T.space("xs"))
	var actions: HBoxContainer = app.modal_footer()

	var plans: Array = app.config.get("plans", [])
	var plan_opt := UI.option(plan_box, "Gói thời gian")
	for p in plans:
		plan_opt.add_item("%s · %d ngày · %s" % [str(p.name), int(p.days), UI.money(p.price)])
	var default_plan := 0
	for i in plans.size():
		if str(plans[i].id) == "month":
			default_plan = i
	plan_opt.selected = default_plan if not plans.is_empty() else -1

	var screen_opt := UI.option(plan_box, "Màn hình game")
	var screen_ids: Array = []
	var def_screen := str(app.uprefs().get("default_screen", ""))
	for sc in screens(app):
		screen_opt.add_item(str(sc.label))
		screen_ids.append(str(sc.id))
		if str(sc.id) == def_screen:
			screen_opt.selected = screen_ids.size() - 1
	screen_opt.get_parent().visible = not screen_ids.is_empty()
	var slot_opt := UI.option(plan_box, "Gắn vào slot")
	var slot_ids: Array = [""]
	slot_opt.add_item("Slot mới — trả theo gói đã chọn")
	for s in app.slots:
		if s.get("tab_id") == null and int(s.expires) > UI.now():
			slot_opt.add_item("Slot trống #%s · %s (đã trả tiền)" % [str(s.id).left(6), UI.time_left(s.expires).to_lower()])
			slot_ids.append(str(s.id))
	slot_opt.get_parent().visible = slot_ids.size() > 1
	if slot_ids.size() > 1:
		slot_opt.selected = 1

	var trial := CheckBox.new()
	var can_trial: bool = bool(app.user.get("trial_approved", 0)) and not bool(app.user.get("trial_used", 0))
	trial.text = "Dùng thử %d phút (miễn phí, một lần)" % int(app.config.get("trial_minutes", 0))
	trial.visible = can_trial
	trial.focus_mode = Control.FOCUS_NONE
	plan_box.add_child(trial)

	var submit := UI.button(null, "Thuê tab", Callable(), "PrimaryButton")
	var coupon := {}
	var update := func() -> void:
		var use_trial := trial.visible and trial.button_pressed
		slot_opt.disabled = use_trial
		if use_trial:
			slot_opt.selected = 0
		var use_slot := slot_opt.selected > 0
		plan_opt.disabled = use_trial or use_slot
		var price := 0
		if not use_trial and not use_slot and plan_opt.selected >= 0:
			price = int(plans[plan_opt.selected].price)
			if not str(coupon.get("code", "")).is_empty():
				price = maxi(0, price - int(coupon.get("discount", 0)))
		coupon_slot.visible = not use_trial and not use_slot
		UI.clear(summary)
		var line := UI.hbox(summary, T.space("sm"))
		UI.label(line, "Thanh toán", "BodyMutedLabel")
		UI.label(line, UI.money(price), "SubheadingLabel", false)
		var balance := int(app.user.get("balance", 0))
		var note := "Số dư hiện tại: %s" % UI.money(balance)
		if use_trial:
			note = "Dùng thử %d phút, không trừ tiền." % int(app.config.get("trial_minutes", 0))
		elif use_slot:
			note = "Dùng slot đã trả tiền, không trừ thêm."
		UI.label(summary, note, "MutedLabel")
		var short := price > balance
		if short:
			UI.label(summary, "Số dư không đủ — hãy nạp thêm %s." % UI.money(price - balance), "DangerLabel")
		submit.disabled = short or (state.game == "custom-jar" and state.jar == "") or app.maintenance_on()

	coupon_box(app, coupon_slot, "rent", func() -> int: return int(plans[maxi(plan_opt.selected, 0)].price) if not plans.is_empty() else 0, update, coupon)
	game_picker(app, picker, state, update, true)
	if not preset_jar.is_empty():
		for j in app.jars:
			if str(j.id) == preset_jar:
				name_input.text = str(j.filename).get_basename().left(60)

	plan_opt.item_selected.connect(func(_i: int) -> void:
		if not str(coupon.get("code", "")).is_empty():
			coupon.recheck.call()
		update.call())
	slot_opt.item_selected.connect(func(_i: int) -> void: update.call())
	trial.toggled.connect(func(_on: bool) -> void: update.call())

	UI.button(actions, "Hủy", app.close_modal, "GhostButton")
	actions.add_child(submit)
	UI.on_press(submit, func() -> void:
		var tab_name := name_input.text.strip_edges()
		if tab_name.is_empty():
			tab_name = "Tab %d" % (app.tabs.size() + 1)
		var data := {
			"name": tab_name,
			"plan": str(plans[maxi(plan_opt.selected, 0)].id) if not plans.is_empty() else "month",
			"trial": trial.visible and trial.button_pressed,
		}
		if state.game != "":
			data["game"] = state.game
		if state.game == "custom-jar":
			data["custom_jar_id"] = state.jar
		if slot_opt.selected > 0:
			data["slot_id"] = slot_ids[slot_opt.selected]
		if screen_opt.selected >= 0 and not screen_ids.is_empty():
			data["screen"] = screen_ids[screen_opt.selected]
		if not str(coupon.get("code", "")).is_empty() and coupon_slot.visible:
			data["coupon"] = coupon.code
		submit.disabled = true
		submit.text = "Đang tạo…"
		var r: Dictionary = await app.act("/tabs", Api.POST, data, ("Đã thuê tab \"%s\". Đang khởi động…" if state.game != "" else "Đã thuê tab \"%s\". Hãy chọn game để bắt đầu.") % tab_name)
		if r.ok:
			app.close_modal()
			app.go("tabs")
		elif is_instance_valid(submit):
			submit.text = "Thuê tab"
			update.call())
	update.call()


# ---------------------------------------------------------------- screen size / rotation

static func screens(app: Node) -> Array:
	return app.config.get("screens", [])


static func screen_info(app: Node, id: String) -> Dictionary:
	for s in screens(app):
		if str(s.id) == id:
			return s
	var sz := screen_size(id)
	return {"id": id, "label": id.replace("x", "×"), "orientation": "landscape" if sz.x > sz.y else "portrait"}


static func screen_size(id: String) -> Vector2i:
	var parts := id.split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(240, 320)


## The same size rotated (240x320 ↔ 320x240) when offered, else the first screen of the other orientation.
static func opposite_screen(app: Node, id: String) -> String:
	var sz := screen_size(id)
	var want := "landscape" if sz.y >= sz.x else "portrait"
	var swapped := "%dx%d" % [sz.y, sz.x]
	for s in screens(app):
		if str(s.id) == swapped:
			return swapped
	for s in screens(app):
		if str(s.get("orientation", "")) == want:
			return str(s.id)
	return ""


static func set_screen(app: Node, tab: Dictionary, screen_id: String) -> Dictionary:
	var r: Dictionary = await app.act("/tabs/" + str(tab.id), Api.PATCH, {"screen": screen_id},
		"Đang xoay màn hình… (%s)" % str(screen_info(app, screen_id).label))
	return r


## "Màn hình" picker: portrait / landscape sizes from config.screens. Calls on_done(screen_id) after saving.
static func pick_screen(app: Node, tab: Dictionary, on_done: Callable = Callable()) -> void:
	var body: VBoxContainer = app.open_modal("Màn hình: %s" % str(tab.name), 520)
	UI.label(body, "Chọn hướng và kích thước màn hình game. Tab khởi động lại với kích thước mới, thời hạn giữ nguyên.", "BodyMutedLabel")
	var current := str(tab.get("screen", ""))
	for orient in [["portrait", "Màn dọc"], ["landscape", "Màn ngang"]]:
		var items := screens(app).filter(func(s: Dictionary) -> bool: return str(s.get("orientation", "")) == orient[0])
		if items.is_empty():
			continue
		UI.label(body, orient[1], "MutedLabel")
		var row := UI.flow(body, T.space("sm"))
		for s in items:
			var sid := str(s.id)
			var b := UI.button(row, str(s.label), func() -> void:
				if sid == current:
					app.close_modal()
					return
				var r: Dictionary = await set_screen(app, tab, sid)
				if r.ok:
					app.close_modal()
					if on_done.is_valid():
						on_done.call(sid), "ChipButtonActive" if sid == current else "ChipButton")
			b.custom_minimum_size.y = UI.target_h(40)
