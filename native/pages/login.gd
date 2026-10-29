extends "res://native/pages/page.gd"
## Sign in / create account. Wide: brand panel + form side by side; narrow: compact brand above the form.
## Nothing technical is shown (no server address, versions or system info).

const GradientBox := preload("res://native/gradient_box.gd")
const FEATURES := [
	["Treo game 24/24", "Tab chạy liên tục trên đám mây, kể cả khi bạn tắt máy."],
	["Game của riêng bạn", "Tải file .jar J2ME hoặc Java PC và chạy ngay."],
	["Chơi ở mọi nơi", "Điều khiển bằng bàn phím Nokia, chạm hoặc bàn phím máy tính."],
]

var register: bool = false
var _form: VBoxContainer
var _error_box: VBoxContainer
var _busy: bool = false
var _wide: bool = false


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 0)
	_layout()


func on_resize() -> void:
	if (app.size.x >= 860 and app.size.y >= 560) != _wide:
		for c in get_children():
			c.queue_free()
		_layout()


func _layout() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, T.space("sm") if app.size.y < 520 and side in ["top", "bottom"] else T.space("lg"))
	center.add_child(margin)

	_wide = app.size.x >= 860 and app.size.y >= 560
	var row: BoxContainer = (HBoxContainer.new() as BoxContainer) if _wide else (VBoxContainer.new() as BoxContainer)
	row.add_theme_constant_override("separation", T.space("xl") if _wide else T.space("lg"))
	margin.add_child(row)
	if _wide:
		_brand_panel(row)
	elif app.size.y >= 520:
		_brand_compact(row)  # short landscape phones: form only, so it fits without scrolling
	var short: bool = app.size.y < 520
	var card := UI.card(row, "Card", T.space("sm") if short else T.space("lg"))
	var panel := card.get_parent() as Control
	panel.custom_minimum_size.x = 400.0 if _wide else minf(420.0, app.size.x - T.space("lg") * 2)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_form = card
	_render_form()


func _brand_panel(parent: Node) -> void:
	var p := PanelContainer.new()
	var bg: StyleBox = GradientBox.new()
	var g := T.gradient()
	bg.set("color_from", Color(g[0], 0.30))
	bg.set("color_to", Color(g[1], 0.12))
	bg.set("radius", float(T.radius("lg")) + 4.0)
	bg.content_margin_left = T.space("xxl")
	bg.content_margin_right = T.space("xxl")
	bg.content_margin_top = T.space("xxl")
	bg.content_margin_bottom = T.space("xxl")
	p.add_theme_stylebox_override("panel", bg)
	p.custom_minimum_size = Vector2(420, 480)
	parent.add_child(p)
	var col := UI.vbox(p, T.space("lg"))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.image(col, load("res://native/icons/app_icon.png"), Vector2(72, 72)).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.wordmark(col, T.font_size("hero"))
	UI.label(col, T.brand("tagline"), "BodyMutedLabel")
	var gap := Control.new()
	gap.custom_minimum_size.y = T.space("sm")
	col.add_child(gap)
	for f in FEATURES:
		var r := UI.hbox(col, T.space("md"))
		var dot := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = T.color("accent_2")
		sb.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", sb)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		r.add_child(dot)
		var t := UI.vbox(r, 2)
		UI.label(t, f[0], "StrongLabel")
		UI.label(t, f[1], "MutedLabel")


func _brand_compact(parent: Node) -> void:
	var col := UI.vbox(parent, T.space("xs"))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.image(col, load("res://native/icons/app_icon.png"), Vector2(56, 56)).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.wordmark(col, T.font_size("xxl")).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t := UI.label(col, T.brand("tagline"), "MutedLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _render_form() -> void:
	UI.clear(_form)
	# Short windows (phone landscape): placeholders instead of field labels, no subtitle — fits without scrolling.
	var short: bool = app.size.y < 520
	var head := UI.vbox(_form, T.space("xs"))
	UI.label(head, "Tạo tài khoản" if register else "Chào mừng trở lại", "SubheadingLabel" if short else "HeadingLabel")
	if not short:
		UI.label(head, "Mật khẩu tối thiểu 10 ký tự." if register else "Đăng nhập để quản lý các tab của bạn.", "MutedLabel")
	var name_input: LineEdit
	if register:
		name_input = _field_input("Tên hiển thị", "Ví dụ: Ninja Pro", false, short)
	var email := _field_input("Email", "ban@email.com", false, short)
	var password := _field_input("Mật khẩu", "Nhập mật khẩu" + (" (tối thiểu 10 ký tự)" if register and short else ""), true, short)
	var ref_input: LineEdit
	if register:
		ref_input = _field_input("Mã giới thiệu (không bắt buộc)", "Ví dụ: AB12CD", false, short)
		ref_input.max_length = 32
	var remember := CheckBox.new()
	remember.text = "Ghi nhớ đăng nhập trên thiết bị này"
	remember.button_pressed = app.remember
	remember.focus_mode = Control.FOCUS_NONE
	remember.toggled.connect(func(on: bool) -> void: app.remember = on)
	_form.add_child(remember)
	_error_box = UI.vbox(_form, T.space("xs"))

	var submit := UI.button(_form, "Tạo tài khoản" if register else "Đăng nhập", Callable(), "PrimaryButton")
	submit.custom_minimum_size.y = UI.target_h(44)
	var do_submit := func() -> void:
		if _busy:
			return
		var creds := {"email": email.text.strip_edges(), "password": password.text}
		if str(creds.email).is_empty() or str(creds.password).is_empty():
			_show_error("Vui lòng nhập email và mật khẩu.")
			return
		_busy = true
		submit.disabled = true
		_show_error("")
		if register:
			creds["name"] = name_input.text.strip_edges()
			if ref_input and not ref_input.text.strip_edges().is_empty():
				creds["ref"] = ref_input.text.strip_edges()
			var reg: Dictionary = await app.api.request("/auth/register", Api.POST, creds)
			if not reg.ok:
				_finish(submit, reg)
				return
		var res: Dictionary = await app.api.request("/auth/login", Api.POST, {"email": creds.email, "password": creds.password})
		if not res.ok:
			_finish(submit, res)
			return
		app.api.token = str(res.data.get("token", ""))
		app.user = res.data.get("user", {})
		app.save_settings()
		await app.enter_app()
	submit.pressed.connect(do_submit)
	email.text_submitted.connect(func(_t: String) -> void: password.grab_focus())
	password.text_submitted.connect(func(_t: String) -> void: do_submit.call())

	var sw := UI.hbox(_form, T.space("xs"))
	sw.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label(sw, "Đã có tài khoản?" if register else "Chưa có tài khoản?", "MutedLabel", false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(sw, "Đăng nhập" if register else "Đăng ký ngay", func() -> void:
		register = not register
		_render_form(), "GhostButton")
	_render_support()
	if not app.api.online:
		_show_error(Api.NETWORK_ERROR, true)


func _field_input(title: String, hint: String, secret: bool, short: bool) -> LineEdit:
	if not short:
		return UI.field(_form, title, hint, secret)
	var e := LineEdit.new()
	e.placeholder_text = title if title != "Email" else hint
	e.secret = secret
	e.custom_minimum_size.y = UI.target_h(40)
	e.tooltip_text = title
	_form.add_child(e)
	return e


func _finish(submit: Button, res: Dictionary) -> void:
	_busy = false
	if is_instance_valid(submit):
		submit.disabled = false
	_show_error(res.error, res.code == 0)


func _show_error(text: String, network: bool = false) -> void:
	if not is_instance_valid(_error_box):
		return
	UI.clear(_error_box)
	if text.is_empty():
		return
	var row := UI.hbox(_error_box, T.space("sm"))
	UI.label(row, text, "DangerLabel").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if network:
		UI.button(row, "Thử lại", func() -> void:
			await app.retry()
			if is_instance_valid(_error_box) and app.api.online:
				_show_error(""), "GhostButton").custom_minimum_size.y = UI.target_h(32)


func _render_support() -> void:
	var contacts := PackedStringArray()
	var names := {"zalo": "Zalo", "telegram": "Telegram", "email": "Email"}
	for k in names:
		var v := str(app.config.get("support", {}).get(k, "")).strip_edges()
		if not v.is_empty():
			contacts.append("%s %s" % [names[k], v])
	if not contacts.is_empty():
		var c := UI.label(_form, "Cần hỗ trợ? " + " · ".join(contacts), "DimLabel")
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
