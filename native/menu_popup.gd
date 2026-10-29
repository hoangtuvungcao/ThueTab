extends Control
## Overflow menu (tokens.components.popover.menu): icon + label rows, dividers between groups, danger
## items in red as the last group. Keyboard: ↑/↓ move, Enter activates, Esc closes; outside click closes.
## Desktop: anchored to the button (opens upward near the bottom edge). Narrow (≤ 640 px): bottom sheet.
##
## Items: [text, Callable] | [text, [Callable, checked]] | null (divider); optional 3rd element `false`
## disables the row. Icons and danger styling are derived from the label (see ICONS / DANGER).

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")

## Label keyword → nav_icon name (first match wins).
const ICONS := [
	["Đăng xuất", "log-out"], ["Giải phóng", "trash"], ["Xóa", "trash"], ["Xoá", "trash"],
	["Mở khóa", "unlock"], ["Khóa", "lock"], ["Thu hồi", "x"], ["Hủy", "x"], ["Từ chối", "x"], ["Bỏ", "x"],
	["Đổi game", "gamepad"], ["Chọn game", "gamepad"], ["Khởi động lại", "refresh"], ["Dừng", "stop"],
	["Chạy", "play"], ["Bật", "play"], ["Màn hình", "monitor-play"], ["FPS", "monitor-play"],
	["Toàn màn hình", "maximize"], ["Tự động gia hạn", "clock"], ["Gia hạn", "clock"], ["Hẹn giờ", "clock"],
	["Tặng giờ", "clock"], ["Chia sẻ", "share"], ["Nhóm", "folder"], ["Đổi tên", "edit"], ["Sửa", "edit"],
	["Nhật ký", "file-code"], ["Gõ chữ", "keyboard"], ["Tự xoay", "refresh"], ["Chi tiết", "info"],
	["số dư", "wallet"], ["Xác nhận", "check-circle"], ["Duyệt", "check-circle"], ["Chọn", "check-circle"],
	["Tài khoản", "user"], ["Cài đặt", "settings"], ["Hỗ trợ", "life-buoy"], ["Giới thiệu", "user"],
]
## Destructive actions: shown in the danger colour and moved to a final group.
const DANGER := ["Giải phóng", "Xóa", "Xoá", "Khóa tài khoản", "Đăng xuất", "Thu hồi", "Hủy đơn", "Từ chối"]

var items: Array = []
var anchor: Control
var _panel: PanelContainer
var _rows: Array = []


static func icon_for(text: String) -> String:
	for pair in ICONS:
		if text.contains(pair[0]):
			return pair[1]
	return ""


static func is_danger(text: String) -> bool:
	for k in DANGER:
		if text.begins_with(k) or text.contains(" " + k.to_lower()):
			return true
	return false


## Opens a menu for `button` with its items. Returns the popup (already in the tree).
static func open(button: Control, menu_items: Array) -> Control:
	var root := button.get_tree().current_scene as Control
	var m: Control = load("res://native/menu_popup.gd").new()
	m.items = menu_items
	m.anchor = button
	root.add_child(m)
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := size.x <= 640.0
	if sheet:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = T.color("surface_2")
	sb.border_color = T.color("border")
	sb.set_border_width_all(1)
	var r := int(T.compf("popover.menu.radius", 12))
	sb.set_corner_radius_all(r)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.35 if T.mode == "dark" else 0.14)
	sb.shadow_size = 12
	if sheet:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.corner_radius_top_left = 20
		sb.corner_radius_top_right = 20
		sb.content_margin_top = 12
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_bottom = 12 + float(get_tree().current_scene.get("_insets").size.y)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_panel.add_child(col)
	if sheet:
		var hc := CenterContainer.new()
		hc.custom_minimum_size.y = 12
		col.add_child(hc)
		var bar := PanelContainer.new()
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = Color(T.color("muted"), 0.5)
		hsb.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("panel", hsb)
		bar.custom_minimum_size = Vector2(36, 4)
		hc.add_child(bar)
	_build_rows(col, sheet)
	_place(sheet)
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus.call_deferred()
	if bool(get_tree().current_scene.get("motion")):
		_panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.12)
		if sheet:
			var y := _panel.position.y
			_panel.position.y += 40
			tw.tween_property(_panel, "position:y", y, 0.18)


## Groups split by null; danger rows are collected into one final group.
func _build_rows(col: VBoxContainer, sheet: bool) -> void:
	var groups: Array = [[]]
	var danger: Array = []
	for it in items:
		if it == null:
			if not groups[-1].is_empty():
				groups.append([])
			continue
		if is_danger(str(it[0])):
			danger.append(it)
		else:
			groups[-1].append(it)
	if not danger.is_empty():
		groups.append(danger)
	var first := true
	var row_h := maxf(T.compf("popover.menu.item_height", 40), T.compf("button.touch_min", 44) if sheet else 0.0)
	for g in groups:
		if g.is_empty():
			continue
		if not first:
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 9)
			col.add_child(sep)
		first = false
		for it in g:
			_row(col, it, row_h)


func _row(col: VBoxContainer, it: Array, row_h: float) -> void:
	var text := str(it[0])
	var cb: Variant = it[1]
	var checked := false
	var action: Callable
	if cb is Array:
		action = cb[0]
		checked = bool(cb[1])
	else:
		action = cb
	var danger := is_danger(text)
	var ink := T.color("danger") if danger else T.color("ink")
	var b := Button.new()
	b.theme_type_variation = "MenuItem"
	b.custom_minimum_size = Vector2(T.compf("popover.menu.min_width", 200) - 12, row_h)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.disabled = it.size() > 2 and it[2] == false
	col.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(T.compf("button.gap", 8)) + 2)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var icon := icon_for(text)
	var isz := T.compf("popover.menu.icon", 18)
	UI.nav_icon(row, icon if not icon.is_empty() else "dot", Color(ink, 0.9 if danger else 0.75), isz)
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_FILL
	l.add_theme_color_override("font_color", ink)
	l.add_theme_font_size_override("font_size", T.font_size("md"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	if checked:
		UI.nav_icon(row, "check", T.color("accent"), isz)
	if b.disabled:
		row.modulate.a = 0.45
	# The row is laid over the button, so size the button to the row's content (icon + text + check).
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, row.get_combined_minimum_size().x + 24.0)
	b.pressed.connect(func() -> void:
		close()
		if action.is_valid():
			action.call())
	_rows.append(b)


func _place(sheet: bool) -> void:
	_panel.reset_size()
	var ps := _panel.get_combined_minimum_size()
	if sheet:
		_panel.size = Vector2(size.x, ps.y)
		_panel.position = Vector2(0, size.y - ps.y)
		return
	var w := maxf(ps.x, T.compf("popover.menu.min_width", 200))
	_panel.size = Vector2(w, ps.y)
	var ar := anchor.get_global_rect() if is_instance_valid(anchor) else Rect2(size / 2.0, Vector2.ZERO)
	var x := clampf(ar.end.x - w, 8.0, size.x - w - 8.0)
	var below := ar.end.y + 6.0
	var y := below
	if below + ps.y > size.y - 8.0:
		y = maxf(8.0, ar.position.y - 6.0 - ps.y)  # not enough room below: open upward
	_panel.position = Vector2(x, y)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(anchor):
		anchor.set_meta("menu_open", false)
	queue_free()
