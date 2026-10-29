extends "res://native/pages/page.gd"
## "Đa màn hình": live thumbnails of all running tabs (shared thumb feed, tokens.poll_seconds.wall) and a
## "Điều khiển đồng bộ" keypad that sends one key to every selected tab via POST /tabs/input.

const Actions := preload("res://native/pages/tab_actions.gd")
const Keypad := preload("res://native/pages/keypad.gd")
const MAX_SYNC := 20

var selected: Dictionary = {}  # tab id -> true
var _order: Array = []
var _layout: BoxContainer
var _grid_box: VBoxContainer
var _sync_info: Label


func needs() -> Array:
	return ["jars"]


func build() -> void:
	_layout = HBoxContainer.new()
	add_child(_layout)
	_build_layout()


func running() -> Array:
	var out: Array = []
	for t in app.tabs:
		if UI.display_state(t) in ["running", "queued"]:
			out.append(t)
	return out


func signature() -> Variant:
	var sig: Array = []
	for t in running():
		sig.append([t.id, t.name, UI.display_state(t)])
	return [sig, app.content_width(), app.uprefs().get("wall_columns")]


func on_resize() -> void:
	_build_layout()
	super.on_resize()


func _build_layout() -> void:
	var old := _layout
	_layout = (VBoxContainer.new() as BoxContainer) if app.compact else (HBoxContainer.new() as BoxContainer)
	_layout.add_theme_constant_override("separation", T.space("lg"))
	add_child(_layout)
	old.queue_free()
	_grid_box = UI.vbox(_layout, T.space("md"))
	_grid_box.size_flags_stretch_ratio = 3.0
	var sync := UI.card(_layout, "Card", T.space("sm"))
	var panel := sync.get_parent() as Control
	if not app.compact:
		panel.custom_minimum_size.x = 280
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var head := UI.hbox(sync, T.space("sm"))
	UI.label(head, "Điều khiển đồng bộ", "SubheadingLabel")
	UI.menu_button(head, "Chọn  ▾", [
		["Chọn tất cả", func() -> void: _select_all(true)],
		["Bỏ chọn", func() -> void: _select_all(false)],
	], "GhostButton").custom_minimum_size.y = UI.target_h(32)
	_sync_info = UI.label(sync, "", "MutedLabel")
	Keypad.build(sync, _send_all, true)
	if not app.compact:
		UI.label(sync, "Phím máy tính cũng gửi tới các tab đã chọn.", "DimLabel")
	_update_sync_info()
	render()


func render() -> void:
	if not is_instance_valid(_grid_box):
		return
	UI.clear(_grid_box)
	var tabs := running()
	_order = tabs.map(func(t: Dictionary) -> String: return str(t.id))
	for id in selected.keys():
		if not id in _order:
			selected.erase(id)
	_update_sync_info()
	if tabs.is_empty():
		UI.empty_state(_grid_box, "Chưa có tab nào đang chạy", "Bật một tab để xem màn hình của nó tại đây.", "Về Tab của tôi", func() -> void: app.go("tabs"))
		return
	var grid := GridContainer.new()
	var avail: float = app.content_width() - (0.0 if app.compact else 280.0 + T.space("lg"))
	var pref_cols: Variant = app.uprefs().get("wall_columns", "auto")
	grid.columns = maxi(1, int(avail / 230.0)) if str(pref_cols) == "auto" else mini(int(pref_cols), maxi(1, int(avail / 150.0)))
	grid.add_theme_constant_override("h_separation", T.space("md"))
	grid.add_theme_constant_override("v_separation", T.space("md"))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_box.add_child(grid)
	for t in tabs:
		_tile(grid, t)


func _tile(parent: Node, t: Dictionary) -> void:
	var id := str(t.id)
	var c := UI.card(parent, "CardLive" if selected.has(id) else "Card", T.space("sm"))
	var head := UI.hbox(c, T.space("sm"))
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.set_pressed_no_signal(selected.has(id))
	cb.tooltip_text = "Chọn để điều khiển đồng bộ"
	cb.toggled.connect(func(on: bool) -> void:
		if on:
			selected[id] = true
		else:
			selected.erase(id)
		c.get_parent().theme_type_variation = "CardLive" if on else "Card"
		_update_sync_info())
	head.add_child(cb)
	UI.label_clip(head, str(t.name), "StrongLabel")
	UI.status_badge(head, t)
	var screen := Button.new()
	screen.focus_mode = Control.FOCUS_NONE
	screen.custom_minimum_size.y = 200
	screen.tooltip_text = "Mở màn hình %s" % str(t.name)
	screen.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	screen.pressed.connect(func() -> void: app.go("viewer", {"id": id}))
	var sb := StyleBoxFlat.new()
	sb.bg_color = T.color("screen")
	sb.set_corner_radius_all(T.radius("md"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var s2: StyleBoxFlat = sb.duplicate()
		if state in ["hover", "hover_pressed"]:
			s2.border_color = Color(T.color("accent_2"), 0.7)
			s2.set_border_width_all(1)
		screen.add_theme_stylebox_override(state, s2)
	c.add_child(screen)
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 4
	rect.offset_top = 4
	rect.offset_right = -4
	rect.offset_bottom = -4
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(rect)
	app.thumbs.subscribe(id, rect, app.tab_kind(t) == "midp")


func _select_all(on: bool) -> void:
	selected.clear()
	if on:
		for id in _order.slice(0, MAX_SYNC):
			selected[id] = true
	_signature = ""
	on_data()


func _update_sync_info() -> void:
	if is_instance_valid(_sync_info):
		_sync_info.text = ("Đang chọn %d tab." % selected.size()) if not selected.is_empty() else "Tích chọn các tab để gửi cùng một phím."


func _send_all(key: String) -> void:
	if selected.is_empty():
		app.toast("Hãy chọn ít nhất một tab.", true)
		return
	app.key_feedback()
	var ids: Array = selected.keys().slice(0, MAX_SYNC)
	var r: Dictionary = await app.api.request("/tabs/input", Api.POST, {"tab_ids": ids, "key": key}, 8.0)
	if not r.ok:
		app.toast(r.error, true)
	elif is_instance_valid(_sync_info):
		_sync_info.text = "Đã gửi tới %d tab." % int(r.data.get("sent", ids.size()))


func on_key(event: InputEvent) -> void:
	var code := Keypad.code_for_event(event)
	if code.is_empty() or selected.is_empty():
		return
	get_viewport().set_input_as_handled()
	_send_all(code)
