extends "res://native/pages/page.gd"
## "Cài đặt": personal preferences stored on the account (PATCH /me/prefs, synced with the web) and
## applied immediately. "Tự xoay theo thiết bị" is per-device (saved locally).

const Actions := preload("res://native/pages/tab_actions.gd")


func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 1 if app.content_width() < 760 else 2
	grid.add_theme_constant_override("h_separation", T.space("lg"))
	grid.add_theme_constant_override("v_separation", T.space("lg"))
	add_child(grid)
	var p: Dictionary = app.uprefs()

	var look := _section(grid, "Giao diện", "Thay đổi được áp dụng ngay và đồng bộ với bản web.")
	_choice(look, "Chủ đề", [["dark", "Tối"], ["light", "Sáng"], ["system", "Theo hệ thống"]], p.theme, "theme")
	var accents: Array = []
	for id in T.accents():
		accents.append([id, str(T.accents()[id].get("label", id))])
	_choice(look, "Màu nhấn", accents, p.accent, "accent", true)
	_choice(look, "Cỡ chữ", [[90, "90%"], [100, "100%"], [110, "110%"], [125, "125%"]], p.font_scale, "font_scale")
	_choice(look, "Mật độ", [["comfortable", "Thoải mái"], ["compact", "Gọn"]], p.density, "density")
	_toggle(look, "Giảm chuyển động", "Tắt hiệu ứng chuyển trang, hộp thoại và thông báo.", p.reduce_motion, "reduce_motion")

	var game := _section(grid, "Màn hình game", "")
	_choice(game, "FPS mặc định", [[30, "30 FPS"], [60, "60 FPS"]], p.default_fps, "default_fps")
	_toggle(game, "Hiện số FPS khi xem", "", p.show_fps, "show_fps")
	_choice(game, "Cỡ bàn phím", [["sm", "Nhỏ"], ["md", "Vừa"], ["lg", "Lớn"]], p.keypad_size, "keypad_size")
	_toggle(game, "Rung khi bấm phím", "Trên điện thoại.", p.haptics, "haptics")
	_toggle(game, "Âm thanh phím", "", p.sounds, "sounds")
	var screens: Array = app.config.get("screens", [])
	if not screens.is_empty():
		var box := UI.vbox(game, T.space("xs") + 2)
		UI.label(box, "Màn hình mặc định khi thuê tab", "MutedLabel")
		var opt := OptionButton.new()
		opt.custom_minimum_size.y = UI.target_h(40)
		opt.focus_mode = Control.FOCUS_NONE
		opt.clip_text = true
		box.add_child(opt)
		for i in screens.size():
			opt.add_item(str(screens[i].label))
			if str(screens[i].id) == str(p.default_screen):
				opt.selected = i
		opt.item_selected.connect(func(i: int) -> void: app.set_user_pref("default_screen", str(screens[i].id)))
	var auto := CheckBox.new()
	auto.text = "Tự xoay theo thiết bị (máy này)"
	auto.tooltip_text = "Khi cửa sổ/điện thoại xoay ngang hoặc dọc, tự chuyển màn hình game theo."
	auto.button_pressed = bool(app.pref("auto_rotate", false))
	auto.focus_mode = Control.FOCUS_NONE
	auto.toggled.connect(func(on: bool) -> void: app.set_pref("auto_rotate", on))
	game.add_child(auto)

	var general := _section(grid, "Chung", "")
	var pages: Array = []
	for item in app.nav_items() + app.user_menu_items():
		if str(item.id) != "settings":
			pages.append([str(item.id), str(item.label)])
	_option(general, "Trang mở đầu", pages, p.start_page, "start_page")
	_choice(general, "Số cột ở Đa màn hình", [["auto", "Tự động"], [2, "2"], [3, "3"], [4, "4"]], p.wall_columns, "wall_columns")
	_choice(general, "Cảnh báo sắp hết hạn", [[0, "Tắt"], [6, "6 giờ"], [12, "12 giờ"], [24, "24 giờ"], [48, "48 giờ"]], p.expiry_alert_hours, "expiry_alert_hours")


func _section(parent: Node, title: String, hint: String) -> VBoxContainer:
	var c := UI.card(parent, "Card", T.space("lg"))
	(c.get_parent() as Control).size_flags_vertical = Control.SIZE_FILL
	var head := UI.vbox(c, 2)
	UI.label(head, title, "SubheadingLabel")
	if not hint.is_empty():
		UI.label(head, hint, "MutedLabel")
	return c


## Segmented choice saved to a pref. `swatch` shows the accent colours of tokens.accents entries.
## Prefs from the server are JSON (numbers are floats: 60.0), options are ints (60): compare numbers by value.
static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


func _choice(parent: Node, title: String, options: Array, current: Variant, key: String, swatch: bool = false) -> void:
	var box := UI.vbox(parent, T.space("xs") + 2)
	UI.label(box, title, "MutedLabel")
	var row := UI.flow(box, T.space("xs") + 2)
	for o in options:
		var value: Variant = o[0]
		var active := _same(value, current)
		var b := UI.button(row, str(o[1]), Callable(), "ChipButtonActive" if active else "ChipButton")
		b.set_meta("value", value)
		# Highlight the new choice right away: only look prefs (theme, accent, size) rebuild the page, so FPS,
		# keypad size, columns… kept showing the old choice until the page was opened again.
		b.pressed.connect(func() -> void:
			for other in row.get_children():
				if other is Button and other.has_meta("value"):
					(other as Button).theme_type_variation = "ChipButtonActive" if _same(other.get_meta("value"), value) else "ChipButton"
			if not _same(value, app.uprefs().get(key)):
				app.set_user_pref(key, value))
		b.custom_minimum_size.y = UI.target_h(34)
		if swatch:
			var preset: Dictionary = T.accents().get(str(value), {})
			var img := Image.create(28, 14, false, Image.FORMAT_RGBA8)
			var c1 := Color(str(preset.get("accent", "#888888")))
			var c2 := Color(str(preset.get("accent_2", "#888888")))
			for x in 28:
				for y in 14:
					var dx := absf(x - 13.5)
					var inside := (x < 14 and Vector2(x - 6.5, y - 6.5).length() < 6.5) or (x >= 14 and Vector2(x - 20.5, y - 6.5).length() < 6.5)
					if inside and dx >= 0.0:
						img.set_pixel(x, y, c1 if x < 14 else c2)
			b.icon = ImageTexture.create_from_image(img)


func _toggle(parent: Node, title: String, hint: String, current: Variant, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = title
	cb.button_pressed = bool(current)
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size.y = UI.target_h(32)
	cb.toggled.connect(func(on: bool) -> void: app.set_user_pref(key, on))
	parent.add_child(cb)
	if not hint.is_empty():
		var h := UI.label(parent, hint, "DimLabel")
		h.add_theme_constant_override("line_spacing", 2)


func _option(parent: Node, title: String, options: Array, current: Variant, key: String) -> void:
	var opt := UI.option(parent, title)
	for i in options.size():
		opt.add_item(str(options[i][1]))
		if str(options[i][0]) == str(current):
			opt.selected = i
	opt.item_selected.connect(func(i: int) -> void: app.set_user_pref(key, options[i][0]))
