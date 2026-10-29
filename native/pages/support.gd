extends "res://native/pages/page.gd"
## "Hỗ trợ": the user's support tickets. params.id opens one thread (admins use the same thread view
## from the admin inbox; their replies are marked as staff by the API).

const STATUS := {
	"open": ["Đang chờ hỗ trợ", "warn"],
	"answered": ["Đã trả lời", "success"],
	"closed": ["Đã đóng", "dim"],
}

var _tickets: Array = []
var _ticket: Dictionary = {}
var _list: VBoxContainer
var _thread: VBoxContainer
var _loaded: bool = false


static func status_badge(parent: Node, status: String) -> PanelContainer:
	var st: Array = STATUS.get(status, [status, "muted"])
	return UI.badge(parent, st[0], T.color(st[1]))


func build() -> void:
	if params.has("id"):
		_thread = UI.vbox(self, T.space("md"))
		_load_ticket()
		return
	var bar := UI.hbox(self, T.space("sm"))
	UI.label(bar, "Gửi câu hỏi hoặc báo lỗi — đội hỗ trợ sẽ trả lời tại đây và gửi thông báo cho bạn.", "BodyMutedLabel").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(bar, "+ Tạo yêu cầu", _create_dialog, "PrimaryButton")
	_list = UI.vbox(self, T.space("sm"))
	_load_list()


func signature() -> Variant:
	return null  # tickets are loaded by this page itself (see on_data)


func on_data() -> void:
	# Light polling: refresh the open thread so staff replies appear without leaving the page.
	if params.has("id") and _loaded and str(_ticket.get("status", "")) != "closed":
		_load_ticket(true)


func _load_list() -> void:
	UI.clear(_list)
	UI.label(_list, "Đang tải…", "MutedLabel")
	var r: Dictionary = await app.api.request("/tickets")
	if not is_instance_valid(_list):
		return
	UI.clear(_list)
	if not r.ok:
		UI.label(_list, r.error, "DangerLabel")
		return
	_tickets = r.data if r.data is Array else []
	if _tickets.is_empty():
		UI.empty_state(_list, "Chưa có yêu cầu hỗ trợ", "Khi cần giúp đỡ, tạo yêu cầu và chúng tôi sẽ phản hồi sớm nhất.", "+ Tạo yêu cầu", _create_dialog)
		return
	var c := UI.card(_list, "Card", T.space("xs"))
	for i in _tickets.size():
		var t: Dictionary = _tickets[i]
		if i > 0:
			UI.separator(c)
		var b := UI.button(c, "", func() -> void: app.go("support", {"id": str(t.id)}), "GhostButton")
		b.custom_minimum_size.y = UI.target_h(56)
		var row := UI.hbox(b, T.space("md"))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = T.space("sm")
		row.offset_right = -T.space("sm")
		var col := UI.vbox(row, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI.label_clip(col, str(t.subject), "StrongLabel").mouse_filter = Control.MOUSE_FILTER_IGNORE
		UI.label_clip(col, "%d tin nhắn · cập nhật %s" % [int(t.get("messages_count", 0)), UI.datetime(t.get("updated"))], "DimLabel").mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_badge(row, str(t.status)).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _create_dialog() -> void:
	var body: VBoxContainer = app.open_modal("Tạo yêu cầu hỗ trợ", 560)
	var subject := UI.field(body, "Tiêu đề", "Ví dụ: Tab không hiện màn hình")
	subject.max_length = 120
	UI.label(body, "Nội dung", "MutedLabel")
	var text := TextEdit.new()
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size.y = 140
	text.placeholder_text = "Mô tả vấn đề, tên tab liên quan, thời điểm xảy ra…"
	text.add_theme_font_override("font", preload("res://native/theme.gd").font_regular)
	body.add_child(text)
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var send := UI.button(row, "Gửi yêu cầu", Callable(), "PrimaryButton")
	send.pressed.connect(func() -> void:
		if subject.text.strip_edges().length() < 3 or text.text.strip_edges().is_empty():
			app.toast("Hãy nhập tiêu đề (tối thiểu 3 ký tự) và nội dung.", true)
			return
		send.disabled = true
		var r: Dictionary = await app.api.request("/tickets", Api.POST, {"subject": subject.text.strip_edges(), "body": text.text.strip_edges()})
		if r.ok:
			app.close_modal()
			app.toast("Đã gửi yêu cầu hỗ trợ.")
			app.go("support", {"id": str(r.data.get("id", ""))})
		else:
			app.toast(r.error, true)
			if is_instance_valid(send):
				send.disabled = false)


func _load_ticket(quiet: bool = false) -> void:
	var r: Dictionary = await app.api.request("/tickets/" + str(params.id))
	if not is_instance_valid(_thread) or not is_inside_tree():
		return
	if not r.ok:
		if not quiet:
			UI.clear(_thread)
			UI.label(_thread, r.error, "DangerLabel")
		return
	var sig := JSON.stringify(r.data)
	if quiet and sig == JSON.stringify(_ticket):
		return
	_ticket = r.data
	_loaded = true
	_render_thread()


func _render_thread() -> void:
	UI.clear(_thread)
	var t := _ticket
	var head := UI.hbox(_thread, T.space("md"))
	UI.button(head, "←", func() -> void:
		if params.get("admin", false):
			app.go("admin", {"section": "support"})
		else:
			app.go("support"), "GhostButton")
	var titles := UI.vbox(head, 2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.label_clip(titles, str(t.get("subject", "")), "SubheadingLabel")
	UI.label_clip(titles, "Tạo %s" % UI.datetime(t.get("created")), "DimLabel")
	if app.compact:
		head = UI.hbox(_thread, T.space("md"))  # phones: status + action on their own row
		head.alignment = BoxContainer.ALIGNMENT_END
	status_badge(head, str(t.get("status", "")))
	var closed := str(t.get("status", "")) == "closed"
	if not closed:
		UI.button(head, "Đóng yêu cầu", func() -> void:
			var r: Dictionary = await app.api.request("/tickets/%s/close" % str(t.id), Api.POST)
			if r.ok:
				_ticket = r.data
				_render_thread()
				app.toast("Đã đóng yêu cầu.")
			else:
				app.toast(r.error, true), "GhostButton")

	var msgs := UI.vbox(_thread, T.space("sm"))
	for m in t.get("messages", []):
		_bubble(msgs, m)

	if closed:
		UI.label(_thread, "Yêu cầu đã đóng. Tạo yêu cầu mới nếu bạn cần thêm hỗ trợ.", "MutedLabel")
		return
	var reply := UI.card(_thread, "Card", T.space("sm"))
	var text := TextEdit.new()
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size.y = 84
	text.placeholder_text = "Nhập trả lời…"
	text.add_theme_font_override("font", preload("res://native/theme.gd").font_regular)
	reply.add_child(text)
	var row := UI.hbox(reply, T.space("sm"))
	row.alignment = BoxContainer.ALIGNMENT_END
	var send := UI.button(row, "Gửi", Callable(), "PrimaryButton")
	send.pressed.connect(func() -> void:
		var msg := text.text.strip_edges()
		if msg.is_empty():
			return
		send.disabled = true
		var r: Dictionary = await app.api.request("/tickets/%s/messages" % str(t.id), Api.POST, {"body": msg})
		if r.ok:
			_ticket = r.data
			_render_thread()
		else:
			app.toast(r.error, true)
			if is_instance_valid(send):
				send.disabled = false)


## Chat bubble: the user's messages on the right (accent tint), staff replies on the left (badge).
func _bubble(parent: Node, m: Dictionary) -> void:
	var staff := bool(m.get("staff", false))
	var row := UI.hbox(parent, 0)
	if not staff:
		UI.spacer(row)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = T.color("surface_2") if staff else T.color("accent_soft")
	sb.border_color = Color(T.color("accent_2"), 0.6) if staff else Color(T.color("accent"), 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(T.radius("lg"))
	if staff:
		sb.corner_radius_top_left = 4
	else:
		sb.corner_radius_top_right = 4
	sb.content_margin_left = T.space("md")
	sb.content_margin_right = T.space("md")
	sb.content_margin_top = T.space("sm")
	sb.content_margin_bottom = T.space("sm")
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if staff else Control.SIZE_SHRINK_END
	p.custom_minimum_size.x = minf(520.0, app.content_width() * 0.82)
	row.add_child(p)
	var col := UI.vbox(p, 2)
	var meta := UI.hbox(col, T.space("sm"))
	if staff:
		UI.badge(meta, "Hỗ trợ " + T.brand("name"), T.color("accent_2"))
	else:
		UI.label(meta, "Bạn" if not app.is_admin() else "Khách hàng", "CaptionLabel", false)
	UI.label(meta, UI.datetime(m.get("created")), "DimLabel", false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var body := UI.label(col, str(m.get("body", "")), "")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if staff:
		UI.spacer(row)
