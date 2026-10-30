extends "res://native/pages/page.gd"
## Live game screen in a console-style frame. Frames come from native/stream_source.gd (WebSocket JPEG
## stream, 30/60 fps) which falls back to polling GET /frame (native/frame_source.gd) while connecting.
## Input: Nokia keypad + physical keyboard → /input, text → /text, tap/swipe on the screen → /tap.
## J2ME frames are portrait 240×320 (nearest filter), Java PC 640×480; aspect is always kept.

const Actions := preload("res://native/pages/tab_actions.gd")
const Keypad := preload("res://native/pages/keypad.gd")
const StreamSource := preload("res://native/stream_source.gd")
const TAP_SLOP := 8.0  # screen px: down→up within this distance is a tap, else a swipe

var tab_id: String = ""
var source: Node  # StreamSource (same signals/methods as FrameSource)
var _fps_row: HFlowContainer
var _readout: Label
var _texture: TextureRect
var _stack: Control
var _screen_col: VBoxContainer
var _placeholder: Label
var _frame_info: Label
var _head: HBoxContainer
var _warn: VBoxContainer
var _body: BoxContainer
var _last_frame_at: int = 0
var _ratio: float = 0.0
var _press_at: Variant = null  # Vector2 local position of the pointer-down, or null
var _text_in: LineEdit
var _rotating_to: String = ""  # screen id requested; overlay shown until frames have that size
var _rotating_since: int = 0
var _rot_overlay: PanelContainer
var _auto_timer: Timer  # debounces "Tự xoay theo thiết bị"
var _pad_root: Control  # phone-landscape gamepad layer (lives in app.page_overlay)
var _pad_title: VBoxContainer  # title/readout column, sized to the gutter left of the game
var _pad_top: HBoxContainer
var _numpad: GridContainer
var _pad_main: VBoxContainer
var _mode: String = ""  # "pad" | "side" | "stack"
var _prev_low_processor: bool = false
var _numpad_box: GridContainer  # portrait number pad (collapsible behind "123" on short screens)
var _numpad_forced: bool = false  # user opened it with "123"
var _rot_slot: HBoxContainer  # compact rotate pill inside the header (never its own row)
var _keypad_card: VBoxContainer
var _key_buttons: Array = []
const KEYPAD_ROWS := 8


## Desktop: screen beside the keypad. Phone portrait: screen above the keypad.
func _side_by_side() -> bool:
	return not app.compact


## Phone landscape: full-window game with gamepad-style controls overlaid on the sides.
func _gamepad() -> bool:
	return app.compact and app.size.x > app.size.y


## Touch mode: virtual keys hidden, the player taps/swipes the game itself (like a phone game).
func _pad_off() -> bool:
	return bool(app.pref("pad_off", false))


## Stretch the game over the whole available area (aspect ratio not kept).
func _stretch() -> bool:
	return bool(app.pref("stretch", false))


func _toggle_pad() -> void:
	app.set_pref("pad_off", not _pad_off())
	_layout_body()
	_render_head()
	_fit_screen.call_deferred()


func _toggle_stretch() -> void:
	app.set_pref("stretch", not _stretch())
	if is_instance_valid(_texture):
		_texture.stretch_mode = TextureRect.STRETCH_SCALE if _stretch() else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_render_head()
	_fit_screen.call_deferred()


func _layout_mode() -> String:
	return "pad" if _gamepad() else ("side" if _side_by_side() else "stack")


func build() -> void:
	tab_id = str(params.get("id", ""))
	# The project runs in low-processor mode (redraw on change only); keep full-rate processing while
	# the live stream is on screen so frames are polled and drawn without added latency.
	_prev_low_processor = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	app.set_immersive(app.compact)  # phone: full-screen viewer, keypad below the screen
	_head = UI.hbox(self, T.space("md"))
	_warn = UI.vbox(self, 0)
	_layout_body()
	_render_head()
	source = StreamSource.new()
	source.setup(app.api, tab_id, _fps_pref())
	source.frame.connect(_show_image)
	source.stats.connect(_on_stats)
	source.hello.connect(func(info: Dictionary) -> void:
		if str(info.get("kind", "")) == "midp":
			_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_check_rotated(Vector2i(int(info.get("width", 0)), int(info.get("height", 0)))))
	source.waiting.connect(func(text: String) -> void:
		if UI.now() - _last_frame_at > 20:
			_set_placeholder(text, true)
		_frame_info.text = text)
	source.failed.connect(func(text: String) -> void:
		_frame_info.text = text
		if text.contains("Thao tác"):
			app.toast(text, true))
	add_child(source)
	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.wait_time = 1.5
	_auto_timer.timeout.connect(_auto_rotate)
	add_child(_auto_timer)
	_update_source_state()
	_render_head()
	_apply_orientation_lock()


func needs() -> Array:
	return ["jars"]


func tab() -> Dictionary:
	for t in app.tabs:
		if str(t.id) == tab_id:
			return t
	for t in app.admin.get("tabs", []):
		if str(t.id) == tab_id:
			return t
	return params.get("tab", {})


func is_midp() -> bool:
	return app.tab_kind(tab()) == "midp"


func signature() -> Variant:
	var t := tab()
	if t.is_empty():
		return null
	return [UI.display_state(t), t.get("desired"), t.get("name"), t.get("game"), t.get("custom_jar_id"), t.get("auto_renew"), t.get("screen"), int(t.get("expires", 0)), app.compact]


func render() -> void:
	_render_head()
	_update_source_state()
	_apply_orientation_lock()
	if _pad_root:
		_render_pad_top()


func _exit_tree() -> void:
	OS.low_processor_usage_mode = _prev_low_processor
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
		if get_window().mode == Window.MODE_FULLSCREEN:
			get_window().mode = Window.MODE_WINDOWED
	if is_instance_valid(_pad_root):
		_pad_root.queue_free()
		_pad_root = null


## Phones: lock to landscape while viewing a landscape-sized game; sensor otherwise.
func _apply_orientation_lock() -> void:
	if not OS.has_feature("mobile"):
		return
	var t := tab()
	var land := not t.is_empty() and _rotatable(t) and _tab_landscape(t)
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if land else DisplayServer.SCREEN_SENSOR)


func _toggle_fullscreen() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED if win.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN


func on_resize() -> void:
	if app.immersive != bool(app.compact):
		app.set_immersive(app.compact)
	if _layout_mode() != _mode:
		_layout_body()
	elif _pad_root:
		_pad_root.size = app.page_overlay.size
	_render_head()
	_fit_screen.call_deferred()


## New theme, accent or text size: rebuild the controls around the game in the new colours. The stream
## (source), orientation lock and fullscreen state are kept, so the game is not touched.
func restyle() -> void:
	_layout_body()
	_render_head()
	_update_source_state()
	_fit_screen.call_deferred()


func _update_source_state() -> void:
	var t := tab()
	var st := UI.display_state(t) if not t.is_empty() else ""
	var off := st in ["stopped", "stopping", "expired", "idle"]
	if source:
		source.paused = off
	if off and is_instance_valid(_readout):
		_readout.text = ""
	if st == "idle":
		_set_placeholder("Tab chưa có game. Bấm \"Chọn game\" để bắt đầu.", true)
	elif off:
		_set_placeholder("Tab %s. Bấm \"Chạy\" để xem màn hình." % T.status_label(st).to_lower(), true)


func _render_head() -> void:
	UI.clear(_head)
	var t := tab()
	UI.button(_head, "←" if app.compact else "← Quay lại", func() -> void: app.go("tabs"), "GhostButton")
	var titles := UI.vbox(_head, 2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.label_clip(titles, str(t.get("name", "Tab")), "SubheadingLabel")
	var sub := str(app.game(str(t.get("game", ""))).get("name", ""))
	var kind: String = app.tab_kind(t)
	if kind != "":
		sub = Actions.kind_label(kind) + " · " + sub
	UI.label_clip(titles, sub, "MutedLabel")
	if t.is_empty():
		return
	_rot_slot = UI.hbox(_head, T.space("xs"))
	UI.status_badge(_head, t)
	var left := int(t.get("expires", 0)) - UI.now()
	var alert := int(app.uprefs().get("expiry_alert_hours", 24)) * 3600
	if left > 0 and left < alert and not app.compact:
		UI.badge(_head, UI.time_left(t.expires), T.color("warn")).tooltip_text = "Sắp hết hạn — gia hạn trong menu ⋯"
	if not Actions.is_expired(t):
		var idle := UI.display_state(t) == "idle"
		if not app.compact:
			UI.button(_head, "Chọn game" if idle else "Đổi game", func() -> void: Actions.change_game(app, t), "PrimaryButton" if idle else "")
		var items: Array = []
		if app.compact:
			items.append(["Chọn game" if idle else "Đổi game", func() -> void: Actions.change_game(app, t)])
		if not idle:
			items.append(["Dừng" if str(t.desired) == "running" else "Chạy", func() -> void: Actions.toggle(app, t)])
		if _rotatable(t):
			items.append(["Màn hình (%s)…" % str(Actions.screen_info(app, str(t.get("screen", ""))).label), func() -> void:
				Actions.pick_screen(app, t, _begin_rotation)])
			items.append(["Tự xoay theo thiết bị", [func() -> void:
				app.set_pref("auto_rotate", not bool(app.pref("auto_rotate", false)))
				_render_rotation_hint(tab()), bool(app.pref("auto_rotate", false))]])
		if app.compact:
			items.append(["Gõ chữ…", _text_dialog])
			for f in T.stream("fps_choices", [30, 60]):
				var v := int(f)
				items.append(["%d FPS" % v, [func() -> void:
					app.set_user_pref("default_fps", v)
					source.set_fps(v), v == _fps_pref()]])
		items.append(["Hiện phím ảo", [_toggle_pad, not _pad_off()]])
		items.append(["Lấp đầy màn hình", [_toggle_stretch, _stretch()]])
		if UI.display_state(t) != "idle":
			items.append(["Khởi động lại game", func() -> void: Actions.restart(app, tab())])
		items.append(["Chia sẻ…", func() -> void: Actions.share_dialog(app, tab())])
		items.append(["Toàn màn hình", _toggle_fullscreen])
		items.append(["Nhật ký", func() -> void: Actions.logs(app, t)])
		items.append(["Gia hạn…", func() -> void: Actions.renew(app, t, false)])
		if not app.compact:
			UI.button(_head, "Hiện phím" if _pad_off() else "Ẩn phím", _toggle_pad, "").tooltip_text = \
				"Hiện bàn phím ảo" if _pad_off() else "Ẩn bàn phím ảo — chơi bằng chạm/chuột trên màn hình game"
		var more := UI.menu_button(_head, "⋯", items, "")
		more.custom_minimum_size = Vector2(UI.target_h(44), UI.target_h(38))
	if _auto_timer:
		_render_rotation_hint(t)


# ---------- screen orientation ----------

func _rotatable(t: Dictionary) -> bool:
	return app.tab_kind(t) != "jar" and not Actions.screens(app).is_empty() and UI.display_state(t) != "idle"


func _device_landscape() -> bool:
	return app.size.x > app.size.y


func _tab_landscape(t: Dictionary) -> bool:
	return str(Actions.screen_info(app, str(t.get("screen", "240x320"))).get("orientation", "portrait")) == "landscape"


## When the window/device orientation differs from the game's, offer a one-tap switch (or auto-switch).
func _render_rotation_hint(t: Dictionary) -> void:
	_warn.visible = false
	if not is_instance_valid(_rot_slot):
		return
	UI.clear(_rot_slot)
	if t.is_empty() or not _rotatable(t) or not _rotating_to.is_empty() or Actions.is_expired(t):
		return
	if _device_landscape() == _tab_landscape(t):
		_auto_timer.stop()
		return
	var target := Actions.opposite_screen(app, str(t.get("screen", "240x320")))
	if target.is_empty():
		return
	if bool(app.pref("auto_rotate", false)):
		if _auto_timer.is_stopped():
			_auto_timer.start()
		return
	var to_land := _device_landscape()
	var pill := UI.button(_rot_slot, "↻ Màn ngang" if to_land else "↻ Màn dọc", func() -> void:
		var r: Dictionary = await Actions.set_screen(app, tab(), target)
		if r.ok:
			_begin_rotation(target), "ChipButton")
	pill.tooltip_text = "Cửa sổ đang %s — chuyển game sang màn %s. Bật \"Tự xoay theo thiết bị\" trong menu ⋯ để tự động." % ["ngang" if to_land else "dọc", "ngang" if to_land else "dọc"]
	pill.custom_minimum_size.y = UI.target_h(32)


func _auto_rotate() -> void:
	var t := tab()
	if not is_inside_tree() or t.is_empty() or not _rotating_to.is_empty() or _device_landscape() == _tab_landscape(t):
		return
	var target := Actions.opposite_screen(app, str(t.get("screen", "240x320")))
	if target.is_empty():
		return
	var r: Dictionary = await Actions.set_screen(app, t, target)
	if r.ok:
		_begin_rotation(target)


## One tap back to the portrait size (some games only draw correctly at 240×320).
func _to_portrait() -> void:
	var t := tab()
	var target := Actions.opposite_screen(app, str(t.get("screen", "320x240")))
	if target.is_empty() or not _rotating_to.is_empty():
		return
	var r: Dictionary = await Actions.set_screen(app, t, target)
	if r.ok:
		_begin_rotation(target)


func _begin_rotation(screen_id: String) -> void:
	if not is_inside_tree():
		return
	_rotating_to = screen_id
	_rotating_since = UI.now()
	if is_instance_valid(_rot_overlay):
		_rot_overlay.visible = true
	if is_instance_valid(_rot_slot):
		UI.clear(_rot_slot)


func _check_rotated(size_now: Vector2i) -> void:
	if _rotating_to.is_empty():
		return
	if size_now == Actions.screen_size(_rotating_to) or UI.now() - _rotating_since > 45:
		_rotating_to = ""
		if is_instance_valid(_rot_overlay):
			_rot_overlay.visible = false
		_render_rotation_hint(tab())
		_fit_screen()


func _layout_body() -> void:
	var old := _body
	_mode = _layout_mode()
	_body = (HBoxContainer.new() as BoxContainer) if _mode == "side" else (VBoxContainer.new() as BoxContainer)
	_body.add_theme_constant_override("separation", T.space("lg"))
	add_child(_body)
	move_child(_body, _warn.get_index() + 1)
	if old:
		old.queue_free()
	if is_instance_valid(_pad_root):
		_pad_root.queue_free()
		_pad_root = null
	_head.visible = _mode != "pad"
	_warn.visible = _mode != "pad"
	# Phones in landscape: hide the status/navigation bars so the game gets the whole screen.
	if OS.has_feature("mobile"):
		var win := get_window()
		if _mode == "pad" and win.mode == Window.MODE_WINDOWED:
			win.mode = Window.MODE_FULLSCREEN
		elif _mode != "pad" and win.mode == Window.MODE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
	if _mode == "pad":
		_build_gamepad()
		return

	_screen_col = UI.vbox(_body, T.space("sm"))
	_screen_col.size_flags_stretch_ratio = 1.6
	_screen_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_col.resized.connect(_fit_screen)
	var console := PanelContainer.new()
	console.theme_type_variation = "Console"
	console.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_screen_col.add_child(console)
	var inner := UI.vbox(console, T.space("sm"))
	inner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var screen := PanelContainer.new()
	screen.theme_type_variation = "Screen"
	inner.add_child(screen)
	_stack = Control.new()
	_stack.custom_minimum_size = Vector2(240, 320)
	_stack.clip_contents = true
	screen.add_child(_stack)
	var prev_tex: Texture2D = _texture.texture if _texture else null
	_texture = TextureRect.new()
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE if _stretch() else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.texture = prev_tex
	_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture.add_to_group("no_drag_scroll")  # swipes here go to the game, not the page
	_texture.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_texture.gui_input.connect(_on_screen_input)
	_stack.add_child(_texture)
	_placeholder = UI.label(_stack, "Đang tải hình ảnh…", "BodyMutedLabel")
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.visible = prev_tex == null
	_rot_overlay = PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0.72)
	_rot_overlay.add_theme_stylebox_override("panel", rsb)
	_rot_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rot_overlay.visible = not _rotating_to.is_empty()
	var rl := UI.label(_rot_overlay, "Đang xoay màn hình…", "StrongLabel")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stack.add_child(_rot_overlay)
	# Soft keys sit under the bottom corners of the screen, like a phone.
	var soft := UI.hbox(inner, T.space("sm"))
	var l := UI.button(soft, "◤ Mềm trái", func() -> void: send("F1"), "KeyButton")
	l.add_theme_font_size_override("font_size", T.font_size("sm"))
	l.tooltip_text = "F1"
	UI.spacer(soft)
	_texture.tooltip_text = "Chạm hoặc vuốt trực tiếp trên màn hình game"
	var r := UI.button(soft, "Mềm phải ◥", func() -> void: send("F2"), "KeyButton")
	r.add_theme_font_size_override("font_size", T.font_size("sm"))
	r.tooltip_text = "F2"
	_frame_info = UI.label(_screen_col, "", "DimLabel")
	_frame_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_row = UI.flow(_screen_col, T.space("sm"))
	_fps_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_render_fps_row()
	_frame_info.visible = _mode != "stack"

	# Text input (game logins). ASCII only, 1–64 chars.
	var text_row := UI.hbox(_screen_col, T.space("sm"))
	var text_in := LineEdit.new()
	_text_in = text_in
	text_in.placeholder_text = "Gõ chữ vào game (tài khoản, mật khẩu…)"
	text_in.max_length = 64
	text_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_in.custom_minimum_size.y = UI.target_h(40)
	text_row.add_child(text_in)
	var send_text := func() -> void:
		var s := text_in.text
		var err := _validate_text(s)
		if not err.is_empty():
			app.toast(err, true)
			return
		var res: Dictionary = await source.send_text(s)
		if res.ok:
			app.toast("Đã gửi %d ký tự." % s.length())
			if is_instance_valid(text_in):
				text_in.clear()
		else:
			app.toast(res.error, true)
	UI.button(text_row, "Gửi chữ", send_text, "")
	text_in.text_submitted.connect(func(_t: String) -> void: send_text.call())
	if _mode == "stack":
		text_row.visible = false  # phone portrait: "Gõ chữ…" lives in the ⋯ menu to keep the keypad on screen
		_text_in = null

	_key_buttons = []
	_keypad_card = null
	if _mode == "stack":
		if not _pad_off():
			_build_portrait_keys()
		_fit_screen.call_deferred()
		return
	if _pad_off():
		_fit_screen.call_deferred()
		return
	var keys := UI.card(_body, "Card", T.space("md"))
	var panel := keys.get_parent() as Control
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _side_by_side():
		panel.custom_minimum_size.x = 300 if not app.compact else 260
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_keypad_card = keys
	panel.add_to_group("no_drag_scroll")  # sliding between keys must not scroll the page
	var title_row := UI.hbox(keys, T.space("sm"))
	UI.label(title_row, "Bàn phím Nokia", "SubheadingLabel")
	var help := UI.button(title_row, "?", Callable(), "GhostButton")
	help.custom_minimum_size = Vector2(32, 32)
	help.tooltip_text = "Phím tắt: mũi tên, Enter, F1/F2 (phím mềm), 0–9, * #, Backspace (xóa), Esc\nCtrl+Enter gõ chữ · F11 toàn màn hình · Alt+← quay lại"
	_key_buttons = Keypad.build(keys, func(code: String) -> void: send(code), false, false, str(app.uprefs().get("keypad_size", "md")))

	_fit_screen.call_deferred()


## The screen keeps the frame aspect (portrait J2ME vs landscape Java PC) and fits the column + window.
func _fps_pref() -> int:
	# JSON numbers are floats (30.0) while the buttons store ints (60): compare as ints, or 60 never matches.
	var choices: Array[int] = []
	for c in T.stream("fps_choices", [30, 60]):
		choices.append(int(c))
	var v := int(app.uprefs().get("default_fps", T.stream("default_fps", 30)))
	return v if v in choices else int(T.stream("default_fps", 30))


func _render_fps_row() -> void:
	UI.clear(_fps_row)
	_readout = UI.label(_fps_row, "Đang kết nối…", "MonoLabel", false)
	_readout.visible = bool(app.uprefs().get("show_fps", true))
	if _mode == "stack":
		return  # FPS choices are in the ⋯ menu on phones
	_readout.add_theme_font_size_override("font_size", T.font_size("xs"))
	var cur := _fps_pref()
	for f in T.stream("fps_choices", [30, 60]):
		var v := int(f)
		var b := UI.button(_fps_row, "%d FPS" % v, func() -> void:
			app.set_user_pref("default_fps", v)
			if source:
				source.set_fps(v)
			_render_fps_row(), "ChipButtonActive" if v == cur else "ChipButton")
		b.custom_minimum_size.y = 28
		b.add_theme_font_size_override("font_size", T.font_size("xs"))


func _on_stats(fps_now: float, ping_ms: int, live: bool) -> void:
	if not is_instance_valid(_readout):
		return
	if live:
		var parts := PackedStringArray(["● Trực tiếp"])
		if _last_frame_at == 0:
			parts.append("đang chờ hình đầu tiên")
		else:
			parts.append("%d fps" % roundi(fps_now))
		if ping_ms >= 0:
			parts.append("%d ms" % ping_ms)
		_readout.text = " · ".join(parts)
		_readout.add_theme_color_override("font_color", T.color("success"))
	else:
		_readout.text = "○ Đang kết nối…"
		_readout.add_theme_color_override("font_color", T.color("muted"))


func _fit_screen() -> void:
	if is_instance_valid(_pad_root):
		_fit_pad()
		return
	if not is_instance_valid(_stack) or not is_instance_valid(_screen_col):
		return
	var fsz: Vector2 = Vector2(640, 480)
	if _texture and _texture.texture:
		fsz = _texture.texture.get_size()
	elif is_midp():
		fsz = Vector2(Actions.screen_size(str(tab().get("screen", "240x320"))))
	var avail_w := _screen_col.size.x - (T.space("md") * 2 + 4)
	if avail_w <= 0.0:
		return
	var max_h: float = maxf(app.size.y - 300.0, 200.0)
	if _mode == "stack":
		max_h = _portrait_room()
	elif _mode == "side":
		var avail := _available_height()
		_fit_keys(avail)
		max_h = maxf(avail - (_screen_col.get_combined_minimum_size().y - _stack.custom_minimum_size.y) - 2.0, 160.0)
	if _stretch():
		var full := Vector2(avail_w, max_h).floor()
		if _stack.custom_minimum_size != full:
			_stack.custom_minimum_size = full
		return
	# Fit inside the column/window keeping aspect; snap to an integer scale for pixel-art frames
	# only when that wastes little room (dense phone screens gain nothing from a smaller integer scale).
	var s := minf(avail_w / fsz.x, max_h / fsz.y)
	var pixel := is_midp() or fsz.y > fsz.x or fsz.x <= 400.0
	if pixel and s >= 1.0 and floorf(s) / s >= 0.95:
		s = floorf(s)
	var want := (fsz * s).floor()
	if _stack.custom_minimum_size != want:
		_stack.custom_minimum_size = want


static func _validate_text(s: String) -> String:
	if s.is_empty():
		return "Hãy nhập nội dung cần gửi."
	if s.length() > 64:
		return "Tối đa 64 ký tự mỗi lần gửi."
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c > 126:
			return "Chỉ gửi được chữ không dấu, số và ký hiệu ASCII (ký tự \"%s\" không hợp lệ)." % s[i]
	return ""


func send(key: String) -> void:
	app.key_feedback()
	var r: Dictionary = await source.send_key(key)
	if not r.ok:
		app.toast(r.error, true)


func on_key(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		# App shortcuts (checked before game keys).
		if k.keycode == KEY_F11:
			var win := get_window()
			win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_LEFT and k.alt_pressed:
			app.go("tabs")
			return
		if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and k.ctrl_pressed and is_instance_valid(_text_in):
			_text_in.grab_focus()
			get_viewport().set_input_as_handled()
			return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var code := Keypad.code_for_event(event)
	if code.is_empty():
		return
	get_viewport().set_input_as_handled()
	send(code)


# ---------- touch / mouse on the game screen ----------

## Maps a local position on the TextureRect to frame pixels, honoring KEEP_ASPECT_CENTERED letterboxing.
## Returns null when the point is outside the drawn image.
func _to_frame(local: Vector2) -> Variant:
	var tex := _texture.texture
	if tex == null:
		return null
	var ts := tex.get_size()
	var rs := _texture.size
	# Stretched: each axis has its own scale; otherwise uniform scale, centred.
	var sc := rs / ts
	if _texture.stretch_mode != TextureRect.STRETCH_SCALE:
		sc = Vector2.ONE * minf(sc.x, sc.y)
	var offset := (rs - ts * sc) / 2.0
	var p := (local - offset) / sc
	if p.x < 0 or p.y < 0 or p.x >= ts.x or p.y >= ts.y:
		return null
	return Vector2i(clampi(int(p.x), 0, int(ts.x) - 1), clampi(int(p.y), 0, int(ts.y) - 1))


func _on_screen_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_texture.accept_event()
	if mb.pressed:
		_press_at = mb.position
		return
	if _press_at == null:
		return
	var start: Vector2 = _press_at
	_press_at = null
	var a: Variant = _to_frame(start)
	if a == null:
		return
	var r: Dictionary
	if start.distance_to(mb.position) <= TAP_SLOP:
		r = await source.send_tap(a)
	else:
		var b: Variant = _to_frame(mb.position.clamp(Vector2.ZERO, _texture.size - Vector2.ONE))
		if b == null:
			b = a
		r = await source.send_tap(a, b)
	if not r.ok:
		app.toast(r.error, true)


# ---------- frames ----------

func _show_image(img: Image) -> void:
	if not is_inside_tree():
		return
	# Paletted / transparent PNGs from the emulator would render dark: force opaque RGB.
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var tex := _texture.texture as ImageTexture
	if tex and Vector2i(tex.get_size()) == img.get_size() and tex.get_format() == img.get_format():
		tex.update(img)
	else:
		_texture.texture = ImageTexture.create_from_image(img)
	var portrait := img.get_height() > img.get_width()
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if portrait or is_midp() else CanvasItem.TEXTURE_FILTER_LINEAR
	var ratio := float(img.get_width()) / float(img.get_height())
	if absf(ratio - _ratio) > 0.01:
		_ratio = ratio
		_fit_screen()
	_last_frame_at = UI.now()
	_set_placeholder("", false)
	if not _rotating_to.is_empty():
		_check_rotated(img.get_size())
	_frame_info.text = ""


func _set_placeholder(text: String, visible_now: bool) -> void:
	if not is_instance_valid(_placeholder):
		return
	_placeholder.visible = visible_now
	if visible_now:
		_placeholder.text = text
		_texture.texture = null
		_frame_info.text = ""



# ---------- phone landscape: gamepad overlay ----------

func _frame_size() -> Vector2:
	if _texture and _texture.texture:
		return _texture.texture.get_size()
	if is_midp():
		return Vector2(Actions.screen_size(str(tab().get("screen", "240x320"))))
	return Vector2(640, 480)


func _pad_style(alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.border_color = Color(1, 1, 1, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(T.radius("lg"))
	return sb


## Semi-transparent ≥ 56 px gamepad button.
func _pad_key(parent: Node, text: String, code: String, size: float = 56.0, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	var normal := _pad_style(0.10)
	if accent:
		normal.bg_color = Color(T.color("accent"), 0.55)
		normal.border_color = Color(T.color("accent_2"), 0.8)
	var pressed := _pad_style(0.28)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_font_size_override("font_size", T.font_size("lg"))
	b.button_down.connect(func() -> void: send(code))
	parent.add_child(b)
	return b


func _build_gamepad() -> void:
	_pad_root = Control.new()
	_pad_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad_root.add_to_group("no_drag_scroll")
	app.page_overlay.add_child(_pad_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad_root.add_child(bg)
	var prev_tex: Texture2D = _texture.texture if _texture else null
	_stack = Control.new()
	_stack.clip_contents = true
	_pad_root.add_child(_stack)
	_texture = TextureRect.new()
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE if _stretch() else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.texture = prev_tex
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if is_midp() else CanvasItem.TEXTURE_FILTER_LINEAR
	_texture.gui_input.connect(_on_screen_input)
	_stack.add_child(_texture)
	_placeholder = UI.label(_stack, "Đang tải hình ảnh…", "BodyMutedLabel")
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.visible = prev_tex == null
	_rot_overlay = PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0.72)
	_rot_overlay.add_theme_stylebox_override("panel", rsb)
	_rot_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rot_overlay.visible = not _rotating_to.is_empty()
	var rl := UI.label(_rot_overlay, "Đang xoay màn hình…", "StrongLabel")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stack.add_child(_rot_overlay)

	var ins: Rect2 = app.get("_insets")
	var m := 12.0
	# Left: D-pad
	var left := GridContainer.new()
	left.columns = 3
	left.add_theme_constant_override("h_separation", 6)
	left.add_theme_constant_override("v_separation", 6)
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_pad_root.add_child(left)
	for k in [["", ""], ["▲", "Up"], ["", ""], ["◀", "Left"], ["OK", "Return"], ["▶", "Right"], ["", ""], ["▼", "Down"], ["", ""]]:
		if k[1] == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(52, 52)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left.add_child(gap)
		else:
			_pad_key(left, k[0], k[1], 52.0)
	left.position = Vector2(ins.position.x + m, 0)
	left.set_meta("side", "left")
	# Right: soft keys + OK + "123" toggle, or the numeric pad
	_pad_main = UI.vbox(null, 8)
	_pad_main.size_flags_horizontal = Control.SIZE_SHRINK_END
	_pad_root.add_child(_pad_main)
	_pad_main.set_meta("side", "right")
	var soft := UI.hbox(_pad_main, 8)
	_pad_key(soft, "◤", "F1", 52.0).tooltip_text = "Phím mềm trái (F1)"
	_pad_key(soft, "◥", "F2", 52.0).tooltip_text = "Phím mềm phải (F2)"
	var ok := _pad_key(_pad_main, "OK", "Return", 64.0, true)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row2 := UI.hbox(_pad_main, 8)
	_pad_key(row2, "C", "BackSpace", 52.0).tooltip_text = "Xóa"
	var tog := Button.new()
	tog.text = "123"
	tog.focus_mode = Control.FOCUS_NONE
	tog.custom_minimum_size = Vector2(52, 52)
	tog.add_theme_stylebox_override("normal", _pad_style(0.10))
	tog.add_theme_stylebox_override("hover", _pad_style(0.10))
	tog.add_theme_stylebox_override("pressed", _pad_style(0.28))
	tog.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	row2.add_child(tog)
	_numpad = GridContainer.new()
	_numpad.columns = 3
	_numpad.add_theme_constant_override("h_separation", 6)
	_numpad.add_theme_constant_override("v_separation", 6)
	_numpad.visible = false
	_pad_root.add_child(_numpad)
	_numpad.set_meta("side", "right")
	for k in [["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"], ["6", "6"], ["7", "7"], ["8", "8"], ["9", "9"], ["*", "asterisk"], ["0", "0"], ["#", "numbersign"]]:
		_pad_key(_numpad, k[0], k[1], 48.0)
	tog.pressed.connect(func() -> void:
		_numpad.visible = not _numpad.visible
		_pad_main.visible = not _numpad.visible
		_place_pad())
	if _pad_off():
		left.visible = false
		_pad_main.visible = false
	# Top bar: back, title/readout, actions
	_pad_top = HBoxContainer.new()
	_pad_top.add_theme_constant_override("separation", 8)
	_pad_root.add_child(_pad_top)
	_frame_info = Label.new()
	_readout = Label.new()
	_fps_row = HFlowContainer.new()  # FPS choices live in the ⋯ menu in this mode
	_render_pad_top()
	_pad_root.resized.connect(_fit_pad)
	_text_in = null
	_fit_pad.call_deferred()


func _render_pad_top() -> void:
	if not is_instance_valid(_pad_top):
		return
	for c in _pad_top.get_children():
		if c != _readout and c != _frame_info:
			c.queue_free()
	for c in [_readout, _frame_info]:
		if c.get_parent():
			c.get_parent().remove_child(c)
	var t := tab()
	var back := Button.new()
	back.text = "←"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(48, 48)
	back.add_theme_stylebox_override("normal", _pad_style(0.10))
	back.add_theme_stylebox_override("hover", _pad_style(0.16))
	back.add_theme_stylebox_override("pressed", _pad_style(0.28))
	back.pressed.connect(func() -> void: app.go("tabs"))
	_pad_top.add_child(back)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mid.add_theme_constant_override("separation", 0)
	mid.clip_contents = true
	_pad_top.add_child(mid)
	_pad_title = mid
	var name_l := UI.label_clip(mid, str(t.get("name", "Tab")), "StrongLabel")
	name_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_readout.add_theme_font_size_override("font_size", T.font_size("xs"))
	_readout.add_theme_color_override("font_color", T.color("success"))
	_readout.visible = bool(app.uprefs().get("show_fps", true))
	mid.add_child(_readout)
	_readout.clip_text = true
	_frame_info.clip_text = true
	_frame_info.add_theme_font_size_override("font_size", T.font_size("xs"))
	_frame_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	mid.add_child(_frame_info)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad_top.add_child(spacer)
	if t.is_empty():
		return
	if _rotatable(t):
		var portrait := not _tab_landscape(t)
		var rot := Button.new()
		# Short label: it must fit the gutter right of the game on narrow phones.
		rot.text = "↻ Ngang" if portrait else "↻ Dọc"
		rot.tooltip_text = "Chuyển sang màn ngang" if portrait else "Quay về màn dọc"
		rot.focus_mode = Control.FOCUS_NONE
		rot.custom_minimum_size.y = 48
		rot.add_theme_stylebox_override("normal", _pad_style(0.14))
		rot.add_theme_stylebox_override("hover", _pad_style(0.2))
		rot.add_theme_stylebox_override("pressed", _pad_style(0.28))
		rot.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		var target := Actions.opposite_screen(app, str(t.get("screen", "240x320")))
		rot.pressed.connect(func() -> void:
			if target.is_empty() or not _rotating_to.is_empty():
				return
			var r: Dictionary = await Actions.set_screen(app, tab(), target)
			if r.ok:
				_begin_rotation(target))
		_pad_top.add_child(rot)
	var keys_btn := Button.new()
	keys_btn.text = "Hiện phím" if _pad_off() else "Ẩn phím"
	keys_btn.tooltip_text = "Hiện phím ảo" if _pad_off() else "Ẩn phím ảo — chơi bằng chạm trên màn hình"
	keys_btn.focus_mode = Control.FOCUS_NONE
	keys_btn.custom_minimum_size.y = 48
	keys_btn.add_theme_stylebox_override("normal", _pad_style(0.14))
	keys_btn.add_theme_stylebox_override("hover", _pad_style(0.2))
	keys_btn.add_theme_stylebox_override("pressed", _pad_style(0.28))
	keys_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	keys_btn.pressed.connect(_toggle_pad)
	_pad_top.add_child(keys_btn)
	var items: Array = []
	items.append(["Đổi game", func() -> void: Actions.change_game(app, tab())])
	items.append(["Hiện phím ảo", [_toggle_pad, not _pad_off()]])
	items.append(["Lấp đầy màn hình", [_toggle_stretch, _stretch()]])
	if _rotatable(t):
		items.append(["Màn hình…", func() -> void: Actions.pick_screen(app, tab(), _begin_rotation)])
		items.append(["Tự xoay theo thiết bị", [func() -> void:
			app.set_pref("auto_rotate", not bool(app.pref("auto_rotate", false)))
			_render_rotation_hint(tab()), bool(app.pref("auto_rotate", false))]])
	items.append(["Gõ chữ…", _text_dialog])
	for f in T.stream("fps_choices", [30, 60]):
		var v := int(f)
		items.append(["%d FPS" % v, [func() -> void:
			app.set_user_pref("default_fps", v)
			source.set_fps(v), v == _fps_pref()]])
	if UI.display_state(t) != "idle":
		items.append(["Khởi động lại game", func() -> void: Actions.restart(app, tab())])
	items.append(["Chia sẻ…", func() -> void: Actions.share_dialog(app, tab())])
	items.append(["Toàn màn hình", _toggle_fullscreen])
	items.append(["Nhật ký", func() -> void: Actions.logs(app, tab())])
	var more := UI.menu_button(_pad_top, "⋯", items, "")
	more.custom_minimum_size = Vector2(48, 48)
	more.add_theme_stylebox_override("normal", _pad_style(0.10))
	more.add_theme_stylebox_override("hover", _pad_style(0.16))
	more.add_theme_stylebox_override("pressed", _pad_style(0.28))


func _text_dialog() -> void:
	var body: VBoxContainer = app.open_modal("Gõ chữ vào game", 440)
	var input := UI.field(body, "Nội dung (chữ không dấu, tối đa 64 ký tự)", "taikhoan123")
	input.max_length = 64
	var row: HBoxContainer = app.modal_footer()
	UI.button(row, "Hủy", app.close_modal, "GhostButton")
	var go_send := func() -> void:
		var err := _validate_text(input.text)
		if not err.is_empty():
			app.toast(err, true)
			return
		var r: Dictionary = await source.send_text(input.text)
		if r.ok:
			app.close_modal()
			app.toast("Đã gửi %d ký tự." % input.text.length())
		else:
			app.toast(r.error, true)
	UI.button(row, "Gửi chữ", go_send, "PrimaryButton")
	input.text_submitted.connect(func(_t: String) -> void: go_send.call())
	input.grab_focus.call_deferred()


## Game fills the window (aspect kept, centred, integer-scaled for pixel art when close); controls overlay.
func _fit_pad() -> void:
	if not is_instance_valid(_pad_root):
		return
	var ins: Rect2 = app.get("_insets")
	var area := Rect2(ins.position, _pad_root.size - ins.position - ins.size)
	var fsz := _frame_size()
	var s := minf(area.size.x / fsz.x, area.size.y / fsz.y)
	if (is_midp() or fsz.x <= 400.0) and s >= 1.0 and floorf(s) / s >= 0.95:
		s = floorf(s)
	var want := area.size.floor() if _stretch() else (fsz * s).floor()
	_stack.size = want
	_stack.position = (area.position + (area.size - want) / 2.0).floor()
	_place_pad()


func _place_pad() -> void:
	if not is_instance_valid(_pad_root):
		return
	var ins: Rect2 = app.get("_insets")
	var sz := _pad_root.size
	var m := 12.0
	_pad_top.position = Vector2(ins.position.x + m, ins.position.y + 8)
	_pad_top.size = Vector2(sz.x - ins.position.x - ins.size.x - m * 2, 48)
	if is_instance_valid(_pad_title) and is_instance_valid(_stack):
		# Title stays in the gutter left of the game instead of drawing over it.
		var gutter := _stack.position.x - _pad_top.position.x - 48.0 - 16.0
		_pad_title.custom_minimum_size.x = maxf(gutter, 40.0)
		_pad_title.visible = gutter >= 40.0
	for c in _pad_root.get_children():
		if not c.has_meta("side") or not (c as Control).visible:
			continue
		var ctl := c as Control
		ctl.reset_size()
		var cs := ctl.get_combined_minimum_size()
		var y := ins.position.y + 56 + (sz.y - ins.position.y - ins.size.y - 56 - cs.y) / 2.0
		if c.get_meta("side") == "left":
			ctl.position = Vector2(ins.position.x + m, y)
		else:
			ctl.position = Vector2(sz.x - ins.size.x - m - cs.x, y)



# ---------- phone portrait: game above a full keypad, everything on one screen ----------

func _build_portrait_keys() -> void:
	var keys := UI.vbox(_body, 6)
	var send_cb := func(code: String) -> void: send(code)
	var h := 44.0
	var dpad := GridContainer.new()
	dpad.columns = 3
	dpad.add_theme_constant_override("h_separation", 6)
	dpad.add_theme_constant_override("v_separation", 6)
	keys.add_child(dpad)
	for k in [["Esc", "Escape"], ["▲", "Up"], ["C", "BackSpace"], ["◀", "Left"], ["OK", "Return"], ["▶", "Right"], ["123", ""], ["▼", "Down"], ["Space", "space"]]:
		var b: Button
		if k[1] == "":
			b = UI.button(dpad, k[0], func() -> void:
				_numpad_forced = not _numpad_box.visible
				_numpad_box.visible = _numpad_forced
				_fit_screen.call_deferred(), "")
		else:
			b = UI.button(dpad, k[0], send_cb.bind(k[1]), "PrimaryButton" if k[1] == "Return" else "KeyButton")
			b.set_meta("instant", true)
		b.custom_minimum_size = Vector2(0, h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_numpad_box = GridContainer.new()
	_numpad_box.columns = 3
	_numpad_box.add_theme_constant_override("h_separation", 6)
	_numpad_box.add_theme_constant_override("v_separation", 6)
	keys.add_child(_numpad_box)
	for k in [["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"], ["6", "6"], ["7", "7"], ["8", "8"], ["9", "9"], ["*", "asterisk"], ["0", "0"], ["#", "numbersign"]]:
		var b := UI.button(_numpad_box, k[0], send_cb.bind(k[1]), "KeyButton")
		b.custom_minimum_size = Vector2(0, h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_numpad_box.visible = true


## Height left for the game after the head, soft keys and keypad (portrait phones). Collapses the
## number pad behind "123" when the game would get too small.
func _portrait_room() -> float:
	var margin: MarginContainer = app.get("_page_margin")
	var pads := float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))
	var viewport_h: float = app.get("_scroll").size.y
	var others := get_combined_minimum_size().y - _stack.custom_minimum_size.y
	var room := viewport_h - pads - others - 2.0
	if is_instance_valid(_numpad_box) and _numpad_box.visible and not _numpad_forced and room < 220.0:
		_numpad_box.visible = false
		room += _numpad_box.get_combined_minimum_size().y + 6.0
	elif is_instance_valid(_numpad_box) and not _numpad_box.visible and not _numpad_forced and room - _numpad_box.get_combined_minimum_size().y - 6.0 >= 260.0:
		_numpad_box.visible = true
		room -= _numpad_box.get_combined_minimum_size().y + 6.0
	return maxf(room, 140.0)



# ---------- desktop: everything fits the window, no page scroll ----------

## Height of the visible page area minus margins, the header row and the gap below it.
func _available_height() -> float:
	var margin: MarginContainer = app.get("_page_margin")
	var pads := float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))
	var viewport_h: float = app.get("_scroll").size.y
	var head_h := _head.get_combined_minimum_size().y if _head.visible else 0.0
	var sep := float(get_theme_constant("separation"))
	return viewport_h - pads - head_h - sep


## Shrinks/grows the keypad keys so the whole keypad card fits `avail` (min 36 px desktop, 48 px touch).
func _fit_keys(avail: float) -> void:
	if _key_buttons.is_empty() or not is_instance_valid(_keypad_card):
		return
	var cur: float = (_key_buttons[0] as Control).custom_minimum_size.y
	var card_h := (_keypad_card.get_parent() as Control).get_combined_minimum_size().y
	var fixed := card_h - cur * KEYPAD_ROWS
	var pref: float = {"sm": 36.0, "md": 42.0, "lg": 54.0}.get(str(app.uprefs().get("keypad_size", "md")), 42.0)
	var lo := 48.0 if UI.touch else 36.0
	var h := clampf(floorf((avail - fixed) / KEYPAD_ROWS), lo, maxf(pref, lo))
	if absf(h - cur) >= 1.0:
		for b in _key_buttons:
			(b as Control).custom_minimum_size.y = h
