extends "res://native/pages/page.gd"
## "Quản trị": stats, workers, JAR review, users, all tabs, audit log. Data: GET /admin/overview.

const Actions := preload("res://native/pages/tab_actions.gd")
const SECTIONS := [["overview", "Tổng quan"], ["orders", "Đơn nạp"], ["jars", "Duyệt JAR"], ["users", "Người dùng"], ["tabs", "Tất cả tab"], ["audit", "Nhật ký"], ["support", "Hỗ trợ"], ["coupons", "Khuyến mãi"], ["growth", "Tăng trưởng"], ["content", "Nội dung & cài đặt"]]

var section: String = "overview"
var _switch: HFlowContainer
var _body: VBoxContainer
var _emails: Dictionary = {}
var _settings: Dictionary = {}  # GET /admin/settings (loaded when the content section opens)
var _settings_loading: bool = false


func needs() -> Array:
	return ["admin"]


var _extra: Dictionary = {}  # per-section data loaded on demand: support / coupons / growth
var _ticket_filter: String = "open"
const PER_PAGE := 20
var _pages: Dictionary = {}  # list key -> current page (kept while switching sections)
var _sys_data: Dictionary = {}
var _sys_box: VBoxContainer  # "Hệ thống" block of the overview (refreshed every 5 s while shown)
var _sys_timer: Timer
var _sys_loading: bool = false


func build() -> void:
	section = str(params.get("section", section))
	_switch = UI.flow(self, T.space("xs") + 2)
	_body = UI.vbox(self, T.space("md"))
	if app.admin.is_empty():
		UI.label(_body, "Đang tải dữ liệu quản trị…", "MutedLabel")


func signature() -> Variant:
	var a: Dictionary = app.admin
	var workers: Array = []
	for w in a.get("workers", []):
		workers.append([w.id, w.capacity, w.online, w.draining, w.used])
	var sig: Variant = null
	match section:
		"overview": sig = [a.get("stats"), workers]
		"jars": sig = a.get("jars")
		"orders": sig = a.get("orders")
		"users": sig = a.get("users")
		"tabs": sig = [a.get("tabs"), int(UI.now() / 60.0)]
		"audit": sig = a.get("audit")
		"content": sig = _settings.is_empty()  # forms must not re-render while editing
		"support", "coupons", "growth": sig = [_extra.has(section), _ticket_filter]  # loaded on demand; forms keep edits
	if section in ["content", "support", "coupons", "growth"]:
		return [section, sig, app.content_width()]
	return [section, sig, app.content_width(), a.get("stats", {}).get("pending_jars")]


func render() -> void:
	if app.admin.is_empty():
		return
	_emails.clear()
	for u in app.admin.get("users", []):
		_emails[str(u.id)] = str(u.email)
	UI.clear(_switch)
	var pending := int(app.admin.get("stats", {}).get("pending_jars", 0))
	for s in SECTIONS:
		var id: String = s[0]
		var text: String = s[1] + ("  %d" % pending if id == "jars" and pending > 0 else "")
		var b := UI.button(_switch, text, func() -> void:
			section = id
			on_data(), "ChipButtonActive" if id == section else "ChipButton")
		b.custom_minimum_size.y = UI.target_h(32)
	UI.clear(_body)
	match section:
		"overview": _overview()
		"jars": _jars()
		"orders": _orders()
		"users": _users()
		"tabs": _tabs()
		"audit": _audit()
		"content": _content()
		"support": _support()
		"coupons": _coupons()
		"growth": _growth()


func _overview() -> void:
	var st: Dictionary = app.admin.get("stats", {})
	var grid := GridContainer.new()
	grid.columns = 2 if app.compact else 3
	grid.add_theme_constant_override("h_separation", T.space("md"))
	grid.add_theme_constant_override("v_separation", T.space("md"))
	_body.add_child(grid)
	UI.stat(grid, "Doanh thu (đã nạp)", UI.money(st.get("total_revenue", 0)))
	UI.stat(grid, "Tổng số dư người dùng", UI.money(st.get("total_users_balance", 0)))
	UI.stat(grid, "Người dùng", str(int(st.get("users", 0))))
	UI.stat(grid, "Tab đang chạy", "%d / %d" % [int(st.get("active_tabs", 0)), int(st.get("total_tabs", 0))])
	UI.stat(grid, "JAR chờ duyệt", str(int(st.get("pending_jars", 0))))
	var online := 0
	for w in app.admin.get("workers", []):
		if w.get("online", false):
			online += 1
	UI.stat(grid, "Worker trực tuyến", "%d / %d" % [online, app.admin.get("workers", []).size()])

	var shead := UI.hbox(_body, T.space("sm"))
	# Single-line labels (no autowrap): a shrunk wrapping label collapses to zero width and stacks its letters.
	UI.label(shead, "Hệ thống", "SubheadingLabel", false).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var hint := UI.label(shead, "· cập nhật mỗi 5 giây", "DimLabel", false)
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sys_box = UI.vbox(_body, T.space("md"))
	UI.label(_sys_box, "Đang tải số liệu…", "MutedLabel")
	if _sys_timer == null:
		_sys_timer = Timer.new()
		_sys_timer.wait_time = 5.0
		_sys_timer.timeout.connect(_load_system)
		add_child(_sys_timer)
	_sys_timer.start()
	_load_system()

	var whead := UI.hbox(_body, T.space("sm"))
	UI.label(whead, "Máy chủ (worker)", "SubheadingLabel")
	UI.button(whead, "+ Thêm worker", _add_worker, "GhostButton")
	var workers: Array = app.admin.get("workers", [])
	if workers.is_empty():
		UI.label(_body, "Chưa có worker nào kết nối.", "MutedLabel")
	for w in workers:
		var c := UI.card(_body, "Card", T.space("sm"))
		var top := UI.hbox(c, T.space("md"))
		var info := UI.vbox(top, 2)
		UI.label(info, str(w.id), "StrongLabel", false)
		UI.label(info, "%d / %d slot đang dùng · %d MB RAM · liên lạc %s" % [int(w.used), int(w.capacity), int(w.get("memory_mb", 0)), UI.datetime(w.get("last_seen"))], "MutedLabel")
		if w.get("draining", 0):
			UI.badge(top, "Ngừng nhận mới", T.color("warn"))
		UI.badge(top, "Trực tuyến" if w.get("online", false) else "Ngoại tuyến", T.color("success") if w.get("online", false) else T.color("danger"))
		var row := UI.flow(c, T.space("md"))
		var cap_box := UI.hbox(row, T.space("sm"))
		UI.label(cap_box, "Sức chứa", "MutedLabel", false)
		var cap := SpinBox.new()
		cap.min_value = 1
		cap.max_value = 100
		cap.value = int(w.capacity)
		cap.custom_minimum_size = Vector2(110, 38)
		cap_box.add_child(cap)
		var drain := CheckBox.new()
		drain.text = "Ngừng nhận tab mới"
		drain.button_pressed = bool(w.get("draining", 0))
		drain.focus_mode = Control.FOCUS_NONE
		row.add_child(drain)
		var wid := str(w.id)
		UI.button(row, "Lưu", func() -> void:
			await app.act("/admin/workers/" + wid, Api.PATCH, {"capacity": int(cap.value), "draining": drain.button_pressed}, "Đã cập nhật worker."), "PrimaryButton")
		UI.button(row, "Xóa", func() -> void:
			app.confirm("Xóa worker", "Xóa worker \"%s\"? Chỉ xóa được khi không còn slot đang thuê." % wid, "Xóa", func() -> void:
				await app.act("/admin/workers/" + wid, Api.DELETE, null, "Đã xóa worker."), true), "GhostButton")


# ---------- live system view (CPU / RAM / disk / network per server, viewers, stream bandwidth) ----------

func _load_system() -> void:
	if section != "overview" or not is_instance_valid(_sys_box) or _sys_loading or not is_visible_in_tree():
		if section != "overview" and _sys_timer:
			_sys_timer.stop()
		return
	_sys_loading = true
	var r: Dictionary = await app.api.request("/admin/system")
	_sys_loading = false
	if not is_instance_valid(_sys_box):
		return
	if not r.ok:
		UI.clear(_sys_box)
		UI.label(_sys_box, "Không tải được số liệu hệ thống: " + str(r.error), "MutedLabel")
		return
	_sys_data = r.data
	_render_system(r.data)


static func _size_mb(v: Variant) -> String:
	var x := float(v)
	return ("%.1f GB" % (x / 1024.0)).replace(".", ",") if x >= 1024.0 else "%d MB" % int(x)


static func _rate(bps: Variant) -> String:
	var x := maxf(float(bps), 0.0)
	if x >= 1048576.0:
		return ("%.1f MB/s" % (x / 1048576.0)).replace(".", ",")
	return "%d KB/s" % int(round(x / 1024.0)) if x >= 1024.0 else "%d B/s" % int(x)


static func _uptime(s: int) -> String:
	if s <= 0:
		return "—"
	var d := s / 86400
	var h := (s % 86400) / 3600
	return "%d ngày %d giờ" % [d, h] if d > 0 else "%d giờ %d phút" % [h, (s % 3600) / 60]


## Bar + caption; green under 70 %, amber under 90 %, red above (same as the web).
func _meter(parent: Node, title: String, pct: int, detail: String) -> void:
	var v := UI.vbox(parent, 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size.x = 170
	var head := UI.hbox(v, T.space("sm"))
	UI.label(head, title, "MutedLabel", false).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(head, "%d%%" % pct, "StrongLabel", false)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = clampi(pct, 0, 100)
	bar.custom_minimum_size.y = 8
	var bg := StyleBoxFlat.new()
	bg.bg_color = T.color("surface_2")
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = T.color("danger") if pct >= 90 else (T.color("warn") if pct >= 70 else T.color("accent"))
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	UI.label(v, detail, "DimLabel")


func _render_system(d: Dictionary) -> void:
	UI.clear(_sys_box)
	var live: Dictionary = d.get("live", {})
	var tabs: Dictionary = d.get("tabs", {})
	var grid := GridContainer.new()
	grid.columns = 2 if app.compact else 4
	grid.add_theme_constant_override("h_separation", T.space("md"))
	grid.add_theme_constant_override("v_separation", T.space("md"))
	_sys_box.add_child(grid)
	UI.stat(grid, "Tab đang chạy", "%d / %d" % [int(tabs.get("running", 0)), int(tabs.get("total", 0))])
	UI.stat(grid, "Đang xem trực tiếp", str(int(live.get("viewers", 0))), "%d tab · %d xem bằng video" % [int(live.get("tabs_watched", 0)), int(live.get("video_viewers", 0))])
	UI.stat(grid, "Băng thông luồng hình", _rate(live.get("out_bps", 0)), "Gửi tới người xem")
	UI.stat(grid, "Luồng từ máy chủ game", str(int(live.get("streams_in", 0))), "%s · %d ô xem trước" % [_rate(live.get("in_bps", 0)), int(live.get("thumbs", 0))])
	for w in d.get("workers", []):
		var s: Dictionary = w.get("system", {})
		var c := UI.card(_sys_box, "Card", T.space("sm"))
		var top := UI.hbox(c, T.space("md"))
		UI.label(top, str(w.id), "StrongLabel", false).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.badge(top, "Trực tuyến" if w.get("online", false) else "Mất kết nối", T.color("success") if w.get("online", false) else T.color("danger"))
		if not s.has("cores"):
			UI.label(c, "Chưa có số liệu — máy chủ cần chạy worker bản mới.", "MutedLabel")
			continue
		var meters := UI.flow(c, T.space("md"))
		var load: Array = s.get("load", [])
		_meter(meters, "CPU · %d nhân" % int(s.cores), int(round(float(s.get("cpu", 0)))), "Tải " + " / ".join(load.map(func(x: Variant) -> String: return "%.2f" % float(x))))
		var mt := float(s.get("mem_total_mb", 0))
		_meter(meters, "RAM", int(round(float(s.get("mem_used_mb", 0)) * 100.0 / maxf(mt, 1.0))), "%s / %s" % [_size_mb(s.get("mem_used_mb", 0)), _size_mb(mt)])
		var disk: Variant = s.get("disk")
		if disk is Dictionary:
			var dt := float(disk.total_mb)
			_meter(meters, "Ổ đĩa (dữ liệu)", int(round(float(disk.used_mb) * 100.0 / maxf(dt, 1.0))), "%s / %s · còn %s" % [_size_mb(disk.used_mb), _size_mb(dt), _size_mb(dt - float(disk.used_mb))])
		var facts := UI.flow(c, T.space("lg"))
		UI.label(facts, "↑ Tải lên %s" % _rate(s.get("net_tx_bps", 0)), "BodyMutedLabel", false)
		UI.label(facts, "↓ Tải xuống %s" % _rate(s.get("net_rx_bps", 0)), "BodyMutedLabel", false)
		UI.label(facts, "Tab %d / %d" % [int(w.get("running", 0)), int(w.get("capacity", 0))], "BodyMutedLabel", false)
		UI.label(facts, "Hoạt động " + _uptime(int(s.get("uptime", 0))), "BodyMutedLabel", false)
		var wtabs: Array = w.get("tabs", [])
		for t in _page_of("sys:" + str(w.id), wtabs, 10):
			var row := UI.hbox(c, T.space("md"))
			var nm := str(t.get("name", "")) if str(t.get("name", "")) != "" else str(t.get("tab_id", "")).left(8)
			UI.label_clip(row, nm).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.label(row, "CPU %s%%" % str(t.get("cpu", 0)), "MonoLabel", false)
			UI.label(row, _size_mb(t.get("mem_mb", 0)), "MonoLabel", false)
		_pager(c, "sys:" + str(w.id), wtabs.size(), 10, func() -> void: _render_system(_sys_data))


# ---------- pagination ----------

## The slice of `items` on the current page of list `key`.
func _page_of(key: String, items: Array, per: int = PER_PAGE) -> Array:
	var pages := maxi(1, ceili(items.size() / float(per)))
	var p := clampi(int(_pages.get(key, 0)), 0, pages - 1)
	_pages[key] = p
	return items.slice(p * per, (p + 1) * per)


## "‹ Trước · Trang 2/5 · 87 mục · Sau ›" under a list; hidden when it fits on one page.
func _pager(parent: Node, key: String, total: int, per: int = PER_PAGE, redraw: Callable = Callable()) -> void:
	var pages := ceili(total / float(per))
	if pages <= 1:
		return
	var p := int(_pages.get(key, 0))
	var go := func(to: int) -> void:
		_pages[key] = to
		if redraw.is_valid():
			redraw.call()
		else:
			render()
	var row := UI.hbox(parent, T.space("sm"))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.button(row, "‹ Trước", go.bind(p - 1), "GhostButton").disabled = p == 0
	UI.label(row, "Trang %d/%d · %d mục" % [p + 1, pages, total], "MutedLabel", false).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.button(row, "Sau ›", go.bind(p + 1), "GhostButton").disabled = p >= pages - 1


func _jars() -> void:
	var jars: Array = app.admin.get("jars", []).duplicate()
	jars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := 0 if str(a.status) == "pending" else 1
		var pb := 0 if str(b.status) == "pending" else 1
		return pa < pb if pa != pb else int(a.created) > int(b.created))
	if jars.is_empty():
		UI.empty_state(_body, "Chưa có file JAR", "Người dùng chưa tải lên file nào.")
		return
	if bool(app.config.get("jar_auto_approve", true)):
		UI.label(_body, "File tải lên được tự động duyệt. Bạn vẫn có thể từ chối file xấu — tab đang dùng file đó sẽ bị dừng.", "MutedLabel")
	for j in _page_of("jars", jars):
		var c := UI.card(_body, "Card", T.space("sm"))
		var top := UI.hbox(c, T.space("md"))
		var info := UI.vbox(top, 2)
		UI.label_clip(info, str(j.filename), "StrongLabel")
		UI.label(info, "%s · %s · %s" % [_emails.get(str(j.get("user_id", "")), "?"), UI.file_size(j.get("file_size", 0)), UI.datetime(j.get("created"))], "MutedLabel")
		UI.label(info, "SHA-256 " + str(j.get("sha256", "")).left(16) + "…", "MonoLabel", false)
		UI.jar_badge(top, str(j.status))
		var row := UI.flow(c)
		var jid := str(j.id)
		var ok := UI.button(row, "Duyệt", func() -> void:
			await app.act("/admin/jars/" + jid, Api.PATCH, {"status": "approved"}, "Đã duyệt file."), "PrimaryButton")
		ok.disabled = str(j.status) == "approved"
		var no := UI.button(row, "Từ chối", func() -> void:
			app.confirm("Từ chối file JAR", "Từ chối \"%s\"? Các tab đang dùng file này sẽ bị dừng." % str(j.filename), "Từ chối", func() -> void:
				await app.act("/admin/jars/" + jid, Api.PATCH, {"status": "rejected"}, "Đã từ chối file."), true), "DangerButton")
		no.disabled = str(j.status) == "rejected"
		UI.button(row, "Xóa file", func() -> void:
			app.confirm("Xóa file JAR", "Xóa \"%s\"? Tab đang dùng file này chuyển về \"Chưa chọn game\"." % str(j.filename), "Xóa", func() -> void:
				await app.act("/admin/jars/" + jid, Api.DELETE, null, "Đã xóa file JAR."), true), "GhostButton")
	_pager(_body, "jars", jars.size())


func _orders() -> void:
	var orders: Array = app.admin.get("orders", [])
	if orders.is_empty():
		UI.empty_state(_body, "Chưa có đơn nạp", "Chưa có người dùng nào tạo đơn nạp tiền.")
		return
	UI.label(_body, "\"Xác nhận tay\" dùng khi khách chuyển khoản sai nội dung: nhập mã giao dịch ngân hàng để cộng tiền.", "MutedLabel")
	var all_orders := orders
	orders = _page_of("orders", all_orders)
	var c := UI.card(_body, "Card", T.space("sm"))
	_pager(_body, "orders", all_orders.size())
	for i in orders.size():
		var o: Dictionary = orders[i]
		if i > 0:
			UI.separator(c)
		var row := UI.flow(c, T.space("sm"))
		var info := UI.vbox(row, 0)
		info.custom_minimum_size.x = 260
		UI.label(info, "%s · %s" % [UI.money(o.amount), str(o.code)], "StrongLabel")
		UI.label(info, "%s · %s" % [_emails.get(str(o.get("user_id", "")), "?"), UI.datetime(o.get("created"))], "DimLabel")
		var st := str(o.status)
		var b := UI.badge(row, T.order_label(st), T.order_color(st))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if st != "paid":
			var oid := str(o.id)
			var code := str(o.code)
			if st == "pending":
				UI.menu_button(row, "⋯", [
					["Xác nhận tay…", func() -> void: _confirm_order(oid, code)],
					["Hủy đơn", func() -> void: await app.act("/admin/orders/%s/cancel" % oid, Api.POST, null, "Đã hủy đơn %s." % code)],
				], "GhostButton").custom_minimum_size.x = UI.target_h(44)
			else:
				UI.button(row, "Xác nhận tay", func() -> void: _confirm_order(oid, code), "GhostButton")


func _confirm_order(oid: String, code: String) -> void:
	var body: VBoxContainer = app.open_modal("Xác nhận tay đơn %s" % code, 440)
	UI.label(body, "Chỉ xác nhận khi đã thấy tiền về tài khoản. Tiền sẽ được cộng vào ví khách.", "BodyMutedLabel")
	var ref := UI.field(body, "Mã giao dịch ngân hàng (tham chiếu)", "Ví dụ: FT24123456789")
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	UI.button(row, "Xác nhận", func() -> void:
		if ref.text.strip_edges().length() < 3:
			app.toast("Mã tham chiếu tối thiểu 3 ký tự.", true)
			return
		var r: Dictionary = await app.act("/admin/orders/%s/confirm" % oid, Api.POST, {"reference": ref.text.strip_edges()}, "Đã xác nhận đơn %s." % code)
		if r.ok:
			app.close_modal(), "PrimaryButton")


func _adjust_balance(u: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Điều chỉnh số dư", 440)
	UI.label(body, "%s · số dư hiện tại %s" % [str(u.email), UI.money(u.balance)], "BodyMutedLabel")
	var amount := UI.field(body, "Số tiền (+ cộng / − trừ), VNĐ", "Ví dụ: 20000 hoặc -5000")
	var reason := UI.field(body, "Lý do (bắt buộc)", "Ví dụ: Bù lỗi máy chủ ngày 20/10")
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	UI.button(row, "Lưu", func() -> void:
		var v := int(amount.text.replace(".", "").replace(",", "").strip_edges())
		if v == 0:
			app.toast("Số tiền phải khác 0.", true)
			return
		if reason.text.strip_edges().length() < 3:
			app.toast("Hãy ghi lý do (tối thiểu 3 ký tự).", true)
			return
		var r: Dictionary = await app.act("/admin/users/%s/balance" % str(u.id), Api.POST, {"amount": v, "reason": reason.text.strip_edges()}, "Đã điều chỉnh số dư.")
		if r.ok:
			app.close_modal(), "PrimaryButton")


func _extend_tab(t: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Tặng giờ: %s" % str(t.name), 420)
	UI.label(body, "Hạn hiện tại: %s (%s)." % [UI.datetime(t.expires), UI.time_left(t.expires).to_lower()], "BodyMutedLabel")
	var row := UI.flow(body)
	for h in [1, 6, 24, 72, 168]:
		var label := "%d giờ" % h if h < 24 else "%d ngày" % int(h / 24.0)
		UI.button(row, "+ " + label, func() -> void:
			var r: Dictionary = await app.act("/admin/tabs/%s/extend" % str(t.id), Api.POST, {"hours": h}, "Đã tặng %s cho %s." % [label, str(t.name)])
			if r.ok:
				app.close_modal(), "ChipButton")


func _users() -> void:
	var all_users: Array = app.admin.get("users", [])
	var users := _page_of("users", all_users)
	var c := UI.card(_body, "Card", T.space("sm"))
	_pager(_body, "users", all_users.size())
	for i in users.size():
		var u: Dictionary = users[i]
		if i > 0:
			UI.separator(c)
		var row := UI.flow(c, T.space("sm"))
		var info := UI.vbox(row, 0)
		info.custom_minimum_size.x = 240
		UI.label(info, "%s · %s" % [str(u.name), str(u.email)], "StrongLabel")
		UI.label(info, "Số dư %s · tạo %s" % [UI.money(u.balance), UI.datetime(u.get("created"))], "DimLabel")
		var badges := UI.hbox(row, T.space("xs"))
		badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if str(u.role) == "admin":
			UI.badge(badges, "Quản trị", T.color("info"))
		if u.get("blocked", 0):
			UI.badge(badges, "Đã khóa", T.color("danger"))
		if u.get("trial_used", 0):
			UI.badge(badges, "Đã dùng thử", T.color("dim"))
		elif u.get("trial_approved", 0):
			UI.badge(badges, "Được dùng thử", T.color("accent"))
		var uid := str(u.id)
		var items: Array = [["Chi tiết & chỉnh sửa…", func() -> void: _user_detail(uid)], ["Cộng/trừ số dư…", func() -> void: _adjust_balance(u)]]
		if not u.get("trial_used", 0):
			var approved := bool(u.get("trial_approved", 0))
			items.append(["Hủy quyền dùng thử" if approved else "Duyệt dùng thử %d phút" % int(app.config.get("trial_minutes", 0)), func() -> void:
				await app.act("/admin/users/" + uid, Api.PATCH, {"trial_approved": not approved}, "Đã cập nhật quyền dùng thử.")])
		var blocked := bool(u.get("blocked", 0))
		items.append(["Mở khóa" if blocked else "Khóa tài khoản…", func() -> void:
			if blocked:
				await app.act("/admin/users/" + uid, Api.PATCH, {"blocked": false}, "Đã mở khóa tài khoản.")
			else:
				app.confirm("Khóa tài khoản", "Khóa %s sẽ đăng xuất mọi phiên và dừng toàn bộ tab của người dùng." % str(u.email), "Khóa", func() -> void:
					await app.act("/admin/users/" + uid, Api.PATCH, {"blocked": true}, "Đã khóa tài khoản."), true)])
		UI.button(row, "Chi tiết", func() -> void: _user_detail(uid), "")
		UI.menu_button(row, "⋯", items, "GhostButton").custom_minimum_size.x = UI.target_h(44)


func _tabs() -> void:
	var tabs: Array = app.admin.get("tabs", [])
	if tabs.is_empty():
		UI.empty_state(_body, "Chưa có tab nào", "Hệ thống chưa có tab.")
		return
	var all_tabs := tabs
	tabs = _page_of("tabs", all_tabs)
	var c := UI.card(_body, "Card", T.space("sm"))
	_pager(_body, "tabs", all_tabs.size())
	for i in tabs.size():
		var t: Dictionary = tabs[i]
		if i > 0:
			UI.separator(c)
		var row := UI.flow(c, T.space("sm"))
		var info := UI.vbox(row, 0)
		info.custom_minimum_size.x = 240
		UI.label(info, str(t.name), "StrongLabel")
		UI.label(info, "%s · %s · %s · %s" % [_emails.get(str(t.get("user_id", "")), "?"), str(app.game(str(t.game)).name), str(t.get("worker_id", "")), UI.time_left(t.expires)], "DimLabel")
		var b := UI.status_badge(row, t)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI.button(row, "Màn hình", func() -> void: app.go("viewer", {"id": str(t.id), "tab": t}), "GhostButton")
		var items: Array = [["Tặng giờ…", func() -> void: _extend_tab(t)]]
		if not Actions.is_expired(t):
			items.append(["Dừng" if str(t.desired) == "running" else "Chạy", func() -> void: Actions.toggle(app, t)])
		items.append(null)
		items.append(["Xóa tab cưỡng chế…", func() -> void: _force_delete_tab(t)])
		UI.menu_button(row, "⋯", items, "GhostButton").custom_minimum_size.x = UI.target_h(44)


func _audit() -> void:
	var rows: Array = app.admin.get("audit", [])
	if rows.is_empty():
		UI.label(_body, "Chưa có hoạt động.", "MutedLabel")
		return
	var page := _page_of("audit", rows)
	var c := UI.card(_body, "Card", T.space("xs"))
	_pager(_body, "audit", rows.size())
	for i in page.size():
		var a: Dictionary = page[i]
		var row := UI.hbox(c, T.space("md"))
		var when := UI.label(row, UI.datetime(a.get("created")), "MonoLabel", false)
		when.custom_minimum_size.x = 140
		var act := UI.label(row, str(a.action), "StrongLabel", false)
		act.custom_minimum_size.x = 150
		UI.label(row, "%s → %s" % [_emails.get(str(a.actor), str(a.actor)), str(a.get("target", "")).left(24)], "MutedLabel")



# ---------------------------------------------------------------- content & settings editor

func _content() -> void:
	if _settings.is_empty():
		UI.label(_body, "Đang tải nội dung…", "MutedLabel")
		if not _settings_loading:
			_settings_loading = true
			var r: Dictionary = await app.api.request("/admin/settings")
			_settings_loading = false
			if r.ok and r.data is Dictionary:
				_settings = r.data
				_signature = ""
				on_data()
			else:
				app.toast(r.error, true)
		return
	var grid := GridContainer.new()
	grid.columns = 1 if app.content_width() < 900 else 2
	grid.add_theme_constant_override("h_separation", T.space("lg"))
	grid.add_theme_constant_override("v_separation", T.space("lg"))
	_body.add_child(grid)
	_site_form(grid)
	var right := UI.vbox(grid, T.space("lg"))
	_support_form(right)
	_presets_form(right)
	_plans_form(_body)


func _save_setting(key: String, value: Variant, ok_text: String) -> bool:
	var r: Dictionary = await app.api.request("/admin/settings/" + key, Api.PUT, value)
	if r.ok:
		_settings[key] = r.data
		app.toast(ok_text)
		await app.load_public()
	else:
		app.toast(r.error, true)
	return r.ok


static func _area(parent: Node, title: String, text: String, height: float = 84.0) -> TextEdit:
	var box := UI.vbox(parent, T.space("xs") + 2)
	UI.label(box, title, "MutedLabel")
	var t := TextEdit.new()
	t.text = text
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size.y = height
	t.add_theme_font_override("font", preload("res://native/theme.gd").font_regular)
	t.add_theme_font_size_override("font_size", T.font_size("md"))
	box.add_child(t)
	return t


func _site_form(parent: Node) -> void:
	var site: Dictionary = _settings.get("site", {}).duplicate(true)
	var c := UI.card(parent, "Card", T.space("md"))
	UI.label(c, "Trang giới thiệu & thông báo", "SubheadingLabel")
	var ann := UI.field(c, "Thông báo đầu trang (để trống để ẩn)", "Ví dụ: Bảo trì 23:00–23:30 tối nay")
	ann.text = str(site.get("announcement", ""))
	ann.max_length = 300
	var title := UI.field(c, "Tiêu đề chính", "")
	title.text = str(site.get("hero_title", ""))
	title.max_length = 120
	var sub := _area(c, "Mô tả", str(site.get("hero_subtitle", "")))
	var cta := UI.field(c, "Nút kêu gọi", "Bắt đầu ngay")
	cta.text = str(site.get("cta", ""))
	cta.max_length = 40
	var footer := UI.field(c, "Chân trang", "")
	footer.text = str(site.get("footer", ""))
	UI.label(c, "Câu hỏi thường gặp", "StrongLabel")
	var faq_box := UI.vbox(c, T.space("sm"))
	var rows: Array = []
	var add_row := func(q: String, a: String) -> void:
		var item := UI.card(faq_box, "CardInset", T.space("xs"))
		var head := UI.hbox(item, T.space("sm"))
		var qi := LineEdit.new()
		qi.text = q
		qi.placeholder_text = "Câu hỏi"
		qi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qi.custom_minimum_size.y = UI.target_h(38)
		head.add_child(qi)
		var ai := _area(item, "Trả lời", a, 64)
		var entry := {"q": qi, "a": ai, "node": item.get_parent()}
		rows.append(entry)
		UI.button(head, "Xóa", func() -> void:
			rows.erase(entry)
			entry.node.queue_free(), "DangerButton")
	for f in site.get("faq", []):
		add_row.call(str(f.get("q", "")), str(f.get("a", "")))
	UI.button(c, "+ Thêm câu hỏi", func() -> void: add_row.call("", ""), "GhostButton").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var save := UI.button(c, "Lưu nội dung", Callable(), "PrimaryButton")
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(func() -> void:
		var faq: Array = []
		for r in rows:
			var q := str(r.q.text).strip_edges()
			if not q.is_empty():
				faq.append({"q": q, "a": str(r.a.text).strip_edges()})
		site["announcement"] = ann.text.strip_edges()
		site["hero_title"] = title.text.strip_edges()
		site["hero_subtitle"] = sub.text.strip_edges()
		site["cta"] = cta.text.strip_edges()
		site["footer"] = footer.text.strip_edges()
		site["faq"] = faq
		save.disabled = true
		await _save_setting("site", site, "Đã lưu nội dung trang.")
		if is_instance_valid(save):
			save.disabled = false)


func _support_form(parent: Node) -> void:
	var sup: Dictionary = _settings.get("support", {})
	var c := UI.card(parent, "Card", T.space("md"))
	UI.label(c, "Liên hệ hỗ trợ", "SubheadingLabel")
	UI.label(c, "Mục để trống sẽ được ẩn trên web và ứng dụng.", "MutedLabel")
	var inputs := {}
	for k in [["zalo", "Zalo"], ["telegram", "Telegram"], ["facebook", "Facebook"], ["email", "Email"], ["hotline", "Hotline"]]:
		var f := UI.field(c, k[1], "")
		f.text = str(sup.get(k[0], ""))
		inputs[k[0]] = f
	var save := UI.button(c, "Lưu liên hệ", Callable(), "PrimaryButton")
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(func() -> void:
		var out := {}
		for k in inputs:
			out[k] = str(inputs[k].text).strip_edges()
		await _save_setting("support", out, "Đã lưu liên hệ hỗ trợ."))


func _presets_form(parent: Node) -> void:
	var c := UI.card(parent, "Card", T.space("md"))
	UI.label(c, "Mức nạp nhanh", "SubheadingLabel")
	var f := UI.field(c, "Các mức (VNĐ), cách nhau bằng dấu phẩy — 1 đến 8 mức, 10.000–5.000.000", "20000, 50000, 100000")
	f.text = ", ".join(PackedStringArray(_settings.get("topup_presets", []).map(func(x: Variant) -> String: return str(int(x)))))
	var save := UI.button(c, "Lưu mức nạp", Callable(), "PrimaryButton")
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(func() -> void:
		var vals: Array = []
		for part in f.text.split(","):
			var v := part.strip_edges().replace(".", "")
			if v.is_valid_int():
				vals.append(int(v))
		await _save_setting("topup_presets", vals, "Đã lưu mức nạp nhanh."))


func _plans_form(parent: Node) -> void:
	var c := UI.card(parent, "Card", T.space("md"))
	UI.label(c, "Bảng giá", "SubheadingLabel")
	UI.label(c, "Mã gói chỉ gồm a–z, 0–9, - và _. Cần ít nhất một gói đang bán.", "MutedLabel")
	var table := UI.vbox(c, T.space("sm"))
	var rows: Array = []
	var header := UI.hbox(table, T.space("sm"))
	for h in [["Mã", 110], ["Tên gói", 0], ["Ngày", 90], ["Giá (đ)", 120], ["Nhãn", 110], ["Bán", 50], ["", 64]]:
		var l := UI.label(header, h[0], "CaptionLabel", false)
		if h[1] > 0:
			l.custom_minimum_size.x = h[1]
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_row := func(p: Dictionary) -> void:
		var row := UI.hbox(table, T.space("sm"))
		var id := LineEdit.new()
		id.text = str(p.get("id", ""))
		id.placeholder_text = "vd: week"
		id.custom_minimum_size = Vector2(110, UI.target_h(38))
		row.add_child(id)
		var nm := LineEdit.new()
		nm.text = str(p.get("name", ""))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size.y = UI.target_h(38)
		row.add_child(nm)
		var days := SpinBox.new()
		days.min_value = 1
		days.max_value = 365
		days.value = int(p.get("days", 30))
		days.custom_minimum_size.x = 90
		row.add_child(days)
		var price := SpinBox.new()
		price.min_value = 0
		price.max_value = 10000000
		price.step = 500
		price.value = int(p.get("price", 0))
		price.custom_minimum_size.x = 120
		row.add_child(price)
		var badge := LineEdit.new()
		badge.text = str(p.get("badge", ""))
		badge.max_length = 24
		badge.custom_minimum_size = Vector2(110, UI.target_h(38))
		row.add_child(badge)
		var active := CheckBox.new()
		active.button_pressed = bool(p.get("active", true))
		active.focus_mode = Control.FOCUS_NONE
		active.custom_minimum_size.x = 50
		row.add_child(active)
		var entry := {"id": id, "name": nm, "days": days, "price": price, "badge": badge, "active": active, "node": row}
		rows.append(entry)
		var del := UI.button(row, "Xóa", func() -> void:
			rows.erase(entry)
			row.queue_free(), "DangerButton")
		del.custom_minimum_size.x = 64
	for p in _settings.get("plans", []):
		add_row.call(p)
	var foot := UI.hbox(c, T.space("sm"))
	UI.button(foot, "+ Thêm gói", func() -> void: add_row.call({"days": 30, "price": 9000, "active": true}), "GhostButton")
	UI.spacer(foot)
	var save := UI.button(foot, "Lưu bảng giá", Callable(), "PrimaryButton")
	save.pressed.connect(func() -> void:
		var out: Array = []
		for r in rows:
			out.append({"id": str(r.id.text).strip_edges().to_lower(), "name": str(r.name.text).strip_edges(),
				"days": int(r.days.value), "price": int(r.price.value), "badge": str(r.badge.text).strip_edges(),
				"active": bool(r.active.button_pressed)})
		await _save_setting("plans", out, "Đã lưu bảng giá."))



# ---------------------------------------------------------------- user management

func _add_worker() -> void:
	var body: VBoxContainer = app.open_modal("Thêm worker", 420)
	var id := UI.field(body, "Mã worker (a–z, 0–9, -)", "vd: vn-hn-2")
	var cap := SpinBox.new()
	cap.min_value = 1
	cap.max_value = 100
	cap.value = 4
	UI.label(body, "Sức chứa (số tab)", "MutedLabel")
	body.add_child(cap)
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	UI.button(row, "Thêm", func() -> void:
		var r: Dictionary = await app.act("/admin/workers", Api.POST, {"id": id.text.strip_edges().to_lower(), "capacity": int(cap.value)}, "Đã thêm worker.")
		if r.ok:
			app.close_modal(), "PrimaryButton")


func _force_delete_tab(t: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Xóa tab cưỡng chế", 460)
	UI.label(body, "Xóa tab \"%s\" ở mọi trạng thái. Không thể hoàn tác." % str(t.name), "BodyMutedLabel")
	var rel := CheckBox.new()
	rel.text = "Giải phóng luôn slot đã trả tiền"
	rel.focus_mode = Control.FOCUS_NONE
	body.add_child(rel)
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	UI.button(row, "Xóa tab", func() -> void:
		var r: Dictionary = await app.act("/admin/tabs/%s?release_slot=%s" % [str(t.id), "true" if rel.button_pressed else "false"], Api.DELETE, null, "Đã xóa tab.")
		if r.ok:
			app.close_modal(), "DangerButton")


## User detail: profile edit, reset password (shown once), force logout, block, delete (type email to confirm).
func _user_detail(uid: String) -> void:
	var body: VBoxContainer = app.open_modal("Người dùng", 760)
	var loading := UI.label(body, "Đang tải…", "MutedLabel")
	var r: Dictionary = await app.api.request("/admin/users/" + uid)
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	loading.queue_free()
	if not r.ok:
		UI.label(body, r.error, "DangerLabel")
		return
	var d: Dictionary = r.data
	var u: Dictionary = d.get("user", {})
	var stats := GridContainer.new()
	stats.columns = 2 if app.compact else 4
	stats.add_theme_constant_override("h_separation", T.space("sm"))
	stats.add_theme_constant_override("v_separation", T.space("sm"))
	body.add_child(stats)
	UI.stat(stats, "Số dư", UI.money(u.get("balance", 0)))
	UI.stat(stats, "Tab", "%d (%d chạy)" % [int(u.get("tabs", d.get("tabs", []).size())), int(u.get("running", 0))])
	UI.stat(stats, "Đã nạp", UI.money(u.get("paid", 0)))
	UI.stat(stats, "Phiên đăng nhập", str(u.get("sessions", 0)))
	UI.label(body, "Tạo %s · đăng nhập gần nhất %s" % [UI.datetime(u.get("created")), UI.datetime(u.get("last_login"))], "MutedLabel")

	var form := UI.card(body, "CardInset", T.space("sm"))
	var name_in := UI.field(form, "Tên", "")
	name_in.text = str(u.get("name", ""))
	var email_in := UI.field(form, "Email", "")
	email_in.text = str(u.get("email", ""))
	var row := UI.flow(form, T.space("md"))
	var role := UI.option(row, "Vai trò")
	role.add_item("Người dùng")
	role.add_item("Quản trị viên")
	role.selected = 1 if str(u.get("role", "")) == "admin" else 0
	role.get_parent().custom_minimum_size.x = 200
	var mt_box := UI.vbox(row, T.space("xs") + 2)
	mt_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.label(mt_box, "Số tab tối đa (0 = mặc định)", "MutedLabel")
	var max_tabs := SpinBox.new()
	max_tabs.min_value = 0
	max_tabs.max_value = 200
	max_tabs.value = int(u.get("max_tabs", 0))
	mt_box.add_child(max_tabs)
	var note := _area(form, "Ghi chú nội bộ", str(u.get("note", "")), 64)
	var save := UI.button(form, "Lưu thay đổi", Callable(), "PrimaryButton")
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(func() -> void:
		await app.act("/admin/users/" + uid, Api.PATCH, {"name": name_in.text.strip_edges(), "email": email_in.text.strip_edges(),
			"role": "admin" if role.selected == 1 else "user", "max_tabs": int(max_tabs.value), "note": note.text.strip_edges()}, "Đã lưu người dùng."))

	UI.label(body, "Thao tác", "StrongLabel")
	var acts := UI.flow(body, T.space("sm"))
	UI.button(acts, "Đặt lại mật khẩu", func() -> void:
		app.confirm("Đặt lại mật khẩu", "Tạo mật khẩu tạm mới cho %s và đăng xuất mọi thiết bị?" % str(u.email), "Đặt lại", func() -> void:
			var res: Dictionary = await app.api.request("/admin/users/%s/password" % uid, Api.POST)
			if not res.ok:
				app.toast(res.error, true)
				return
			var pw := str(res.data.get("password", ""))
			var b2: VBoxContainer = app.open_modal("Mật khẩu tạm", 420)
			UI.label(b2, "Chỉ hiện một lần. Gửi cho người dùng và nhắc họ đổi mật khẩu sau khi đăng nhập.", "BodyMutedLabel")
			var box := UI.card(b2, "CardInset", T.space("xs"))
			var l := UI.label(box, pw, "HeadingLabel")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UI.button(b2, "Sao chép", func() -> void:
				DisplayServer.clipboard_set(pw)
				app.toast("Đã sao chép mật khẩu tạm."), "PrimaryButton")), "")
	UI.button(acts, "Buộc đăng xuất", func() -> void:
		var res: Dictionary = await app.api.request("/admin/users/%s/logout" % uid, Api.POST)
		app.toast(("Đã đăng xuất %d phiên." % int(res.data.get("sessions", 0))) if res.ok else res.error, not res.ok), "")
	var blocked := bool(u.get("blocked", 0))
	UI.button(acts, "Mở khóa" if blocked else "Khóa", func() -> void:
		await app.act("/admin/users/" + uid, Api.PATCH, {"blocked": not blocked}, "Đã mở khóa." if blocked else "Đã khóa tài khoản.")
		_user_detail(uid), "" if blocked else "DangerButton")
	UI.button(acts, "Xóa tài khoản…", func() -> void: _delete_user(u), "DangerButton")

	var tabs: Array = d.get("tabs", [])
	if not tabs.is_empty():
		UI.label(body, "Tab (%d)" % tabs.size(), "StrongLabel")
		var tc := UI.card(body, "CardInset", T.space("xs"))
		for t in tabs:
			var tr := UI.hbox(tc, T.space("sm"))
			UI.label_clip(tr, "%s · %s" % [str(t.name), UI.time_left(t.expires)], "")
			UI.status_badge(tr, t)
			UI.button(tr, "Xóa", func() -> void:
				app.close_modal()
				_force_delete_tab(t), "GhostButton")
	var jars: Array = d.get("jars", [])
	if not jars.is_empty():
		UI.label(body, "File JAR (%d)" % jars.size(), "StrongLabel")
		var jc := UI.card(body, "CardInset", T.space("xs"))
		for j in jars:
			var jr := UI.hbox(jc, T.space("sm"))
			UI.label_clip(jr, "%s · %s" % [str(j.filename), UI.file_size(j.get("file_size", 0))], "")
			UI.jar_badge(jr, str(j.get("status", "")))
			var jid := str(j.id)
			UI.button(jr, "Xóa", func() -> void:
				await app.act("/admin/jars/" + jid, Api.DELETE, null, "Đã xóa file JAR.")
				_user_detail(uid), "GhostButton")


func _delete_user(u: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Xóa tài khoản", 460)
	UI.label(body, "Xóa vĩnh viễn %s cùng toàn bộ tab, slot, file JAR, đơn nạp và lịch sử ví. Không thể hoàn tác." % str(u.email), "BodyMutedLabel")
	var confirm_in := UI.field(body, "Nhập chính xác email để xác nhận", str(u.email))
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var del := UI.button(row, "Xóa vĩnh viễn", Callable(), "DangerButton")
	del.disabled = true
	confirm_in.text_changed.connect(func(t: String) -> void: del.disabled = t.strip_edges().to_lower() != str(u.email).to_lower())
	del.pressed.connect(func() -> void:
		var r: Dictionary = await app.act("/admin/users/" + str(u.id), Api.DELETE, null, "Đã xóa tài khoản.")
		if r.ok:
			app.close_modal())



# ---------------------------------------------------------------- on-demand sections

## Loads `path` into _extra[key] once, then re-renders. Returns true when data is ready.
func _need(key: String, path: String) -> bool:
	if _extra.has(key):
		return true
	UI.label(_body, "Đang tải…", "MutedLabel")
	var r: Dictionary = await app.api.request(path)
	if not is_inside_tree():
		return false
	if r.ok:
		_extra[key] = r.data
		_signature = ""
		on_data()
	else:
		UI.clear(_body)
		UI.label(_body, r.error, "DangerLabel")
	return false


func _reload(key: String) -> void:
	_extra.erase(key)
	_signature = ""
	on_data()


# ---- Hỗ trợ inbox

func _support() -> void:
	if not await _need("support", "/admin/tickets?status=" + _ticket_filter):
		return
	var bar := UI.flow(_body, T.space("xs") + 2)
	for f in [["open", "Đang chờ"], ["answered", "Đã trả lời"], ["closed", "Đã đóng"], ["", "Tất cả"]]:
		var fid: String = f[0]
		UI.button(bar, f[1], func() -> void:
			_ticket_filter = fid
			_reload("support"), "ChipButtonActive" if fid == _ticket_filter else "ChipButton").custom_minimum_size.y = UI.target_h(32)
	var items: Array = _extra.support if _extra.support is Array else []
	if items.is_empty():
		UI.empty_state(_body, "Không có yêu cầu", "Không có yêu cầu hỗ trợ nào ở mục này.")
		return
	var Support: GDScript = load("res://native/pages/support.gd")
	var c := UI.card(_body, "Card", T.space("xs"))
	for i in items.size():
		var t: Dictionary = items[i]
		if i > 0:
			UI.separator(c)
		var row := UI.hbox(c, T.space("md"))
		var col := UI.vbox(row, 0)
		UI.label_clip(col, str(t.subject), "StrongLabel")
		UI.label_clip(col, "%s · %d tin · %s" % [str(t.get("email", "")), int(t.get("messages_count", 0)), UI.datetime(t.get("updated"))], "DimLabel")
		Support.status_badge(row, str(t.status))
		var tid := str(t.id)
		UI.button(row, "Mở", func() -> void: app.go("support", {"id": tid, "admin": true}), "")


# ---- Khuyến mãi (coupons)

const COUPON_KINDS := [["percent", "Giảm % khi thuê"], ["amount", "Giảm tiền khi thuê"], ["topup", "Thưởng khi nạp"]]


static func coupon_text(c: Dictionary) -> String:
	match str(c.get("kind", "")):
		"percent":
			return "Giảm %d%%%s" % [int(c.value), (" (tối đa %s)" % UI.money(c.max_value)) if int(c.get("max_value", 0)) > 0 else ""]
		"amount":
			return "Giảm %s" % UI.money(c.value)
	return "Thưởng %s%s khi nạp" % [("%d%%" % int(c.value)) if int(c.get("max_value", 0)) > 0 else UI.money(c.value), (" (tối đa %s)" % UI.money(c.max_value)) if int(c.get("max_value", 0)) > 0 else ""]


func _coupons() -> void:
	if not await _need("coupons", "/admin/coupons"):
		return
	var head := UI.hbox(_body, T.space("sm"))
	UI.label(head, "Mã giảm giá khi thuê và mã thưởng khi nạp. Người dùng nhập ở ô \"Mã khuyến mãi\".", "BodyMutedLabel").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(head, "+ Tạo mã", func() -> void: _coupon_form({}), "PrimaryButton")
	var items: Array = _extra.coupons.get("coupons", [])
	if items.is_empty():
		UI.empty_state(_body, "Chưa có mã khuyến mãi", "Tạo mã đầu tiên để chạy chương trình ưu đãi.")
		return
	var c := UI.card(_body, "Card", T.space("xs"))
	for i in items.size():
		var cp: Dictionary = items[i]
		if i > 0:
			UI.separator(c)
		var row := UI.flow(c, T.space("sm"))
		var col := UI.vbox(row, 0)
		col.custom_minimum_size.x = 240
		UI.label_clip(col, str(cp.code), "StrongLabel")
		var uses := "%d/%s lượt" % [int(cp.get("used", 0)), str(cp.max_uses) if int(cp.get("max_uses", 0)) > 0 else "∞"]
		var exp_text := "hết hạn " + UI.datetime(cp.expires) if int(cp.get("expires", 0)) > 0 else "không hết hạn"
		UI.label_clip(col, "%s · %s · %s" % [coupon_text(cp), uses, exp_text], "DimLabel")
		var on := bool(cp.get("active", true))
		UI.badge(row, "Đang bật" if on else "Đã tắt", T.color("success") if on else T.color("dim")).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var code := str(cp.code)
		UI.menu_button(row, "⋯", [
			["Sửa…", func() -> void: _coupon_form(cp)],
			["Tắt mã" if on else "Bật mã", func() -> void:
				var body := cp.duplicate()
				body.erase("used")
				body.erase("created")
				body["active"] = not on
				var r: Dictionary = await app.api.request("/admin/coupons/" + code, Api.PUT, body)
				app.toast(("Đã tắt mã." if on else "Đã bật mã.") if r.ok else r.error, not r.ok)
				_reload("coupons")],
			null,
			["Xóa…", func() -> void:
				app.confirm("Xóa mã", "Xóa mã \"%s\"? Lịch sử sử dụng vẫn được giữ." % code, "Xóa", func() -> void:
					var r: Dictionary = await app.api.request("/admin/coupons/" + code, Api.DELETE)
					app.toast("Đã xóa mã." if r.ok else r.error, not r.ok)
					_reload("coupons"), true)],
		], "GhostButton").custom_minimum_size.x = UI.target_h(44)


func _spin(parent: Node, title: String, lo: float, hi: float, value: float, step: float = 1.0) -> SpinBox:
	var box := UI.vbox(parent, T.space("xs") + 2)
	box.custom_minimum_size.x = 160
	UI.label(box, title, "MutedLabel")
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = value
	sp.custom_minimum_size.y = UI.target_h(38)
	box.add_child(sp)
	return sp


func _coupon_form(cp: Dictionary) -> void:
	var editing := not cp.is_empty()
	var body: VBoxContainer = app.open_modal("Sửa mã %s" % str(cp.code) if editing else "Tạo mã khuyến mãi", 560)
	var code := UI.field(body, "Mã (3–32 ký tự: chữ, số, - _)", "VD: TET2027")
	code.text = str(cp.get("code", ""))
	code.editable = not editing
	var kind := UI.option(body, "Loại")
	for i in COUPON_KINDS.size():
		kind.add_item(COUPON_KINDS[i][1])
		if COUPON_KINDS[i][0] == str(cp.get("kind", "percent")):
			kind.selected = i
	var grid := UI.flow(body, T.space("md"))
	var value := _spin(grid, "Giá trị (% hoặc đ)", 1, 10000000, int(cp.get("value", 10)))
	var max_value := _spin(grid, "Giảm/thưởng tối đa (0 = không giới hạn)", 0, 10000000, int(cp.get("max_value", 0)), 1000)
	var min_amount := _spin(grid, "Số tiền tối thiểu", 0, 10000000, int(cp.get("min_amount", 0)), 1000)
	var max_uses := _spin(grid, "Tổng lượt (0 = ∞)", 0, 1000000, int(cp.get("max_uses", 0)))
	var per_user := _spin(grid, "Lượt mỗi người", 0, 1000, int(cp.get("per_user", 1)))
	var days_left := 0
	if int(cp.get("expires", 0)) > 0:
		days_left = maxi(1, int(ceil((int(cp.expires) - UI.now()) / 86400.0)))
	var days := _spin(grid, "Hết hạn sau (ngày, 0 = không)", 0, 3650, days_left)
	var note := UI.field(body, "Ghi chú nội bộ", "")
	note.text = str(cp.get("note", ""))
	var active := CheckBox.new()
	active.text = "Đang bật"
	active.button_pressed = bool(cp.get("active", true))
	active.focus_mode = Control.FOCUS_NONE
	body.add_child(active)
	var foot: HBoxContainer = app.modal_footer()
	UI.button(foot, "Hủy", app.close_modal, "GhostButton")
	UI.button(foot, "Lưu", func() -> void:
		var data := {"code": code.text.strip_edges().to_upper(), "kind": COUPON_KINDS[kind.selected][0], "value": int(value.value),
			"max_value": int(max_value.value), "min_amount": int(min_amount.value), "max_uses": int(max_uses.value),
			"per_user": int(per_user.value), "expires": (UI.now() + int(days.value) * 86400) if int(days.value) > 0 else 0,
			"active": active.button_pressed, "note": note.text.strip_edges()}
		var r: Dictionary
		if editing:
			r = await app.api.request("/admin/coupons/" + str(cp.code), Api.PUT, data)
		else:
			r = await app.api.request("/admin/coupons", Api.POST, data)
		if r.ok:
			app.close_modal()
			app.toast("Đã lưu mã khuyến mãi.")
			_reload("coupons")
		else:
			app.toast(r.error, true), "PrimaryButton")


# ---- Tăng trưởng: broadcast, referral, maintenance

func _growth() -> void:
	if not await _need("growth", "/admin/growth"):
		return
	var g: Dictionary = _extra.growth
	var grid := GridContainer.new()
	grid.columns = 1 if app.content_width() < 900 else 2
	grid.add_theme_constant_override("h_separation", T.space("lg"))
	grid.add_theme_constant_override("v_separation", T.space("lg"))
	_body.add_child(grid)

	var bc := UI.card(grid, "Card", T.space("md"))
	UI.label(bc, "Gửi thông báo", "SubheadingLabel")
	var target := UI.option(bc, "Người nhận")
	target.add_item("Tất cả người dùng")
	var uids: Array = [""]
	for u in app.admin.get("users", []):
		target.add_item(str(u.email))
		uids.append(str(u.id))
	var title := UI.field(bc, "Tiêu đề", "VD: Khuyến mãi cuối tuần")
	title.max_length = 120
	var text := UI.field(bc, "Nội dung", "")
	text.max_length = 500
	var link := UI.field(bc, "Liên kết (không bắt buộc)", "/wallet")
	link.max_length = 120
	var send := UI.button(bc, "Gửi thông báo", Callable(), "PrimaryButton")
	send.size_flags_horizontal = Control.SIZE_SHRINK_END
	send.pressed.connect(func() -> void:
		if title.text.strip_edges().is_empty():
			app.toast("Hãy nhập tiêu đề.", true)
			return
		var data := {"title": title.text.strip_edges(), "body": text.text.strip_edges(), "link": link.text.strip_edges()}
		if target.selected > 0:
			data["user_id"] = uids[target.selected]
		var go_send := func() -> void:
			var r: Dictionary = await app.api.request("/admin/notifications", Api.POST, data)
			app.toast(("Đã gửi tới %d người." % int(r.data.get("sent", 0))) if r.ok else r.error, not r.ok)
		if target.selected == 0:
			app.confirm("Gửi cho tất cả", "Gửi thông báo \"%s\" tới mọi người dùng?" % data.title, "Gửi", go_send)
		else:
			go_send.call())

	var right := UI.vbox(grid, T.space("lg"))
	var ref: Dictionary = g.get("referral", {})
	var rc := UI.card(right, "Card", T.space("md"))
	UI.label(rc, "Chương trình giới thiệu", "SubheadingLabel")
	var ren := CheckBox.new()
	ren.text = "Đang bật"
	ren.button_pressed = bool(ref.get("enabled", true))
	ren.focus_mode = Control.FOCUS_NONE
	rc.add_child(ren)
	var rrow := UI.flow(rc, T.space("md"))
	var pct := _spin(rrow, "Thưởng người mời (%)", 0, 50, int(ref.get("percent", 10)))
	var cap := _spin(rrow, "Tối đa mỗi người (đ)", 0, 5000000, int(ref.get("max_bonus", 50000)), 1000)
	var refb := _spin(rrow, "Thưởng người được mời (đ)", 0, 1000000, int(ref.get("referee_bonus", 0)), 1000)
	var rsave := UI.button(rc, "Lưu", Callable(), "")
	rsave.size_flags_horizontal = Control.SIZE_SHRINK_END
	rsave.pressed.connect(func() -> void:
		var r: Dictionary = await app.api.request("/admin/settings/referral", Api.PUT,
			{"enabled": ren.button_pressed, "percent": int(pct.value), "max_bonus": int(cap.value), "referee_bonus": int(refb.value)})
		app.toast("Đã lưu chương trình giới thiệu." if r.ok else r.error, not r.ok)
		if r.ok:
			await app.load_public())

	var m: Dictionary = g.get("maintenance", {})
	var mc := UI.card(right, "Card", T.space("md"))
	UI.label(mc, "Chế độ bảo trì", "SubheadingLabel")
	UI.label(mc, "Khi bật: mọi người thấy thông báo; người dùng thường không thể thuê tab, mua slot hay tải file.", "MutedLabel")
	var men := CheckBox.new()
	men.text = "Bật bảo trì"
	men.button_pressed = bool(m.get("enabled", false))
	men.focus_mode = Control.FOCUS_NONE
	mc.add_child(men)
	var msg := UI.field(mc, "Thông báo", "Hệ thống đang bảo trì…")
	msg.text = str(m.get("message", ""))
	msg.max_length = 300
	var hrs := 0
	if int(m.get("until", 0)) > UI.now():
		hrs = int(ceil((int(m.until) - UI.now()) / 3600.0))
	var until := _spin(mc, "Dự kiến xong sau (giờ, 0 = không ghi)", 0, 720, hrs)
	var msave := UI.button(mc, "Lưu", Callable(), "DangerButton" if not men.button_pressed else "")
	msave.size_flags_horizontal = Control.SIZE_SHRINK_END
	msave.pressed.connect(func() -> void:
		var r: Dictionary = await app.api.request("/admin/settings/maintenance", Api.PUT,
			{"enabled": men.button_pressed, "message": msg.text.strip_edges(), "until": (UI.now() + int(until.value) * 3600) if int(until.value) > 0 else 0})
		app.toast("Đã lưu chế độ bảo trì." if r.ok else r.error, not r.ok)
		if r.ok:
			await app.load_public())

	var top: Array = g.get("top_referrers", [])
	UI.label(_body, "Người giới thiệu nhiều nhất · %d yêu cầu hỗ trợ đang chờ" % int(g.get("open_tickets", 0)), "SubheadingLabel")
	if top.is_empty():
		UI.label(_body, "Chưa có ai giới thiệu bạn bè.", "MutedLabel")
		return
	var tc := UI.card(_body, "Card", T.space("xs"))
	for i in top.size():
		if i > 0:
			UI.separator(tc)
		var row := UI.hbox(tc, T.space("md"))
		UI.label_clip(row, str(top[i].get("email", "")), "")
		UI.label(row, "%d người" % int(top[i].get("invited", 0)), "StrongLabel", false)
