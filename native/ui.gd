extends RefCounted
## Small widget + formatting helpers. All widgets are styled through theme type variations (theme.gd).

const T := preload("res://native/tokens.gd")
const NavIcon := preload("res://native/nav_icon.gd")
const AppTheme := preload("res://native/theme.gd")

static var _icon_cache: Dictionary = {}
static var touch: bool = false  # phone layout: touch targets ≥ tokens components.button.touch_min


## Button size key for a legacy pixel hint: ≤36 → sm, ≤42 → md, larger → lg.
static func size_for(px: float) -> String:
	return "sm" if px <= 36.0 else ("md" if px <= 42.0 else "lg")


## Control height from tokens.components.button[size].height (≥ touch_min on touch layouts).
static func btn_h(size: String = "md") -> float:
	var h := T.compf("button.%s.height" % size, 40)
	return maxf(h, T.compf("button.touch_min", 44)) if touch else h


## Height for a control sized by a legacy pixel hint — mapped onto the token sizes (no magic numbers).
static func target_h(desktop: float = 40.0) -> float:
	return btn_h(size_for(desktop))


## Input height: components.input.height (height_touch on touch layouts).
static func input_h() -> float:
	return T.compf("input.height_touch", 44) if touch else T.compf("input.height", 40)


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func label(parent: Node, text: String, variant: String = "", wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if not variant.is_empty():
		l.theme_type_variation = variant
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent:
		parent.add_child(l)
	return l


## Single-line label that fills available width and ends with "…" when too long (titles, names).
static func label_clip(parent: Node, text: String, variant: String = "") -> Label:
	var l := label(parent, text, variant, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Button sized by tokens.components.button[size] (sm | md | lg); label centred, 8 px icon gap.
static func button(parent: Node, text: String, callback: Callable, variant: String = "", size: String = "md") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = btn_h(size)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if size != "md":
		b.add_theme_font_size_override("font_size", int(T.compf("button.%s.font" % size, 14)))
	if not variant.is_empty():
		b.theme_type_variation = variant
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		b.pressed.connect(func() -> void: _run_busy(b, callback))
	if parent:
		parent.add_child(b)
	return b


## Same as a UI.button callback for buttons wired after creation: locked + spinner while the action waits.
static func on_press(b: Button, callback: Callable) -> void:
	b.pressed.connect(func() -> void: _run_busy(b, callback))


## Runs a button's action; while it waits (e.g. for the server) the button is locked — repeated taps do nothing —
## and after 200 ms its label turns into a spinner. Instant actions (open a dialog, navigate) never show it.
static func _run_busy(b: Button, callback: Callable) -> void:
	# Game keys (meta "instant", or the KeyButton style) must accept rapid repeated presses.
	if b.has_meta("instant") or b.theme_type_variation == "KeyButton":
		callback.call()
		return
	if b.has_meta("busy"):
		return
	b.set_meta("busy", true)
	# State before the action: handlers that disable their own button must not leave it locked afterwards.
	b.set_meta("was_disabled", b.disabled)
	var tree := b.get_tree()
	var done := [false]
	if tree:
		tree.create_timer(0.2).timeout.connect(func() -> void:
			if not done[0] and is_instance_valid(b):
				_show_spinner(b))
	await callback.call()
	done[0] = true
	if not is_instance_valid(b):
		return
	b.remove_meta("busy")
	if b.has_meta("spin"):
		var sp: Control = b.get_meta("spin")
		if is_instance_valid(sp):
			sp.queue_free()
		b.remove_meta("spin")
		b.text = str(b.get_meta("label_text", b.text))
		b.custom_minimum_size.x = float(b.get_meta("min_w", 0.0))
		b.disabled = bool(b.get_meta("was_disabled", false))


static func _show_spinner(b: Button) -> void:
	b.set_meta("label_text", b.text)
	b.set_meta("min_w", b.custom_minimum_size.x)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, b.size.x)  # keep the width: no layout jump
	b.text = ""
	b.disabled = true
	var sp := spinner(minf(18.0, b.size.y * 0.5), b.get_theme_color("font_color"))
	sp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	b.add_child(sp)
	b.set_meta("spin", sp)


## Small rotating arc (loading indicator).
static func spinner(d: float = 18.0, color: Color = Color.WHITE) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.size = Vector2(d, d)
	c.pivot_offset = Vector2(d, d) / 2.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		c.draw_arc(Vector2(d, d) / 2.0, d / 2.0 - 1.5, 0.0, TAU * 0.72, 24, color, 2.0, true))
	c.ready.connect(func() -> void:
		var tw := c.create_tween().set_loops()
		tw.tween_property(c, "rotation", TAU, 0.8).from(0.0))
	return c


static func vbox(parent: Node, sep: int = -1) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.space("md") if sep < 0 else sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent:
		parent.add_child(v)
	return v


static func hbox(parent: Node, sep: int = -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", T.space("md") if sep < 0 else sep)
	if parent:
		parent.add_child(h)
	return h


static func flow(parent: Node, sep: int = -1) -> HFlowContainer:
	var f := HFlowContainer.new()
	var s := T.space("sm") if sep < 0 else sep
	f.add_theme_constant_override("h_separation", s)
	f.add_theme_constant_override("v_separation", s)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent:
		parent.add_child(f)
	return f


static func spacer(parent: Node) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## A card panel; returns the inner VBox. The PanelContainer is its parent.
static func card(parent: Node, variant: String = "Card", sep: int = -1) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variant
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := vbox(p, int(T.compf("card.gap", 12)) if sep < 0 else sep)
	return v


## Square icon-only button: components.button.icon_only[size], icon centred.
static func icon_button(parent: Node, icon: String, callback: Callable, tooltip: String = "", size: String = "md", variant: String = "GhostButton") -> Button:
	var b := button(parent, "", callback, variant, size)
	var side := T.compf("button.icon_only.%s" % size, 40)
	if touch:
		side = maxf(side, T.compf("button.touch_min", 44))
	b.custom_minimum_size = Vector2(side, side)
	b.tooltip_text = tooltip
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	nav_icon(c, icon, T.color("muted"), T.compf("button.%s.icon" % size, 18))
	return b


static func badge(parent: Node, text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := color
	bg.a = 0.15
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(T.compf("badge.radius", 999)))
	var bpx := T.compf("badge.padding_x", 8)
	var bh := T.compf("badge.height", 20)
	s.content_margin_left = bpx
	s.content_margin_right = bpx
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	p.custom_minimum_size.y = bh
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	l.add_theme_font_size_override("font_size", int(T.compf("badge.font", 12)))
	l.add_theme_color_override("font_color", color.lightened(0.1) if T.mode == "dark" else color.darkened(0.25))
	row.add_child(l)
	if parent:
		parent.add_child(p)
	return p


static func field(parent: Node, title: String, placeholder: String = "", secret: bool = false) -> LineEdit:
	var box := vbox(parent, int(T.compf("input.label_gap", 6)))
	label(box, title, "MutedLabel")
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size.y = input_h()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(input)
	return input


static func option(parent: Node, title: String) -> OptionButton:
	var box := vbox(parent, int(T.compf("input.label_gap", 6)))
	label(box, title, "MutedLabel")
	var o := OptionButton.new()
	o.custom_minimum_size.y = input_h()
	o.fit_to_longest_item = false
	o.clip_text = true
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.focus_mode = Control.FOCUS_NONE
	box.add_child(o)
	return o


static func separator(parent: Node) -> void:
	parent.add_child(HSeparator.new())


static func image(parent: Node, tex: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if parent:
		parent.add_child(r)
	return r


static func nav_icon(parent: Node, icon: String, color: Color, size: float = 18.0) -> Control:
	var i: Control = NavIcon.new()
	i.set("icon", icon)
	i.set("color", color)
	i.custom_minimum_size = Vector2(size, size)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if parent:
		parent.add_child(i)
	return i


static func game_icon(icon: String) -> Texture2D:
	var key := icon if not icon.is_empty() else "custom"
	if _icon_cache.has(key):
		return _icon_cache[key]
	var path := "res://native/icons/%s.png" % key
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else load("res://native/icons/custom.png")
	_icon_cache[key] = tex
	return tex


## Small stat tile: caption above a big value.
static func stat(parent: Node, caption: String, value: String, hint: String = "") -> VBoxContainer:
	var v := card(parent, "Card", T.space("xs"))
	label(v, caption, "MutedLabel")
	label(v, value, "StatLabel")
	if not hint.is_empty():
		label(v, hint, "DimLabel")
	return v


## Empty state (components.empty_state): centred icon → title → description → one primary button,
## text column capped at max_width.
static func empty_state(parent: Node, title: String, body: String, action_text: String = "", action: Callable = Callable(), icon: String = "inbox") -> void:
	var v := card(parent)
	var center := CenterContainer.new()
	v.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", T.space("md"))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	# At most 360 wide, but never wider than the card: a fixed 360 overflowed phone screens and pushed the whole
	# page to the right. The width follows the card (the centre's own minimum stays at or below it, so no loop).
	var max_w := minf(T.compf("empty_state.max_width", 360), 360)
	center.resized.connect(func() -> void:
		var want := minf(max_w, center.size.x)
		if absf(col.custom_minimum_size.x - want) >= 1.0:
			col.custom_minimum_size.x = want)
	var pad := Control.new()
	pad.custom_minimum_size.y = T.space("lg")
	col.add_child(pad)
	var ic := nav_icon(col, icon, Color(T.color("muted"), 0.7), T.compf("empty_state.icon", 56))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t := label(col, title, "SubheadingLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := label(col, body, "BodyMutedLabel")
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not action_text.is_empty():
		var bt := button(col, action_text, action, "PrimaryButton")
		bt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pad2 := Control.new()
	pad2.custom_minimum_size.y = T.space("lg")
	col.add_child(pad2)


static func section_title(parent: Node, text: String, hint: String = "") -> void:
	var v := vbox(parent, 2)
	label(v, text, "SubheadingLabel")
	if not hint.is_empty():
		label(v, hint, "MutedLabel")


# ---------- formatting ----------

static func money(value: Variant) -> String:
	var n := int(value)
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if neg else "") + s + out + "đ"


static func now() -> int:
	return int(Time.get_unix_time_from_system())


static func datetime(ts: Variant) -> String:
	if ts == null:
		return "—"
	var local := int(ts) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	return "%02d/%02d/%04d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]


static func time_left(expires: Variant) -> String:
	var secs := int(expires) - now()
	if secs <= 0:
		return "Đã hết hạn"
	var days := floori(secs / 86400.0)
	var hours := floori((secs % 86400) / 3600.0)
	var mins := floori((secs % 3600) / 60.0)
	if days > 0:
		return "Còn %d ngày %d giờ" % [days, hours]
	if hours > 0:
		return "Còn %d giờ %d phút" % [hours, mins]
	return "Còn %d phút" % maxi(1, mins)


static func file_size(bytes: Variant) -> String:
	var b := float(bytes)
	if b >= 1048576.0:
		return "%.1f MB" % (b / 1048576.0)
	return "%d KB" % int(ceil(b / 1024.0))


## One display state per tab: expired > stopping/stopped (owner asked to stop) > worker-reported status.
static func display_state(tab: Dictionary) -> String:
	if int(tab.get("expires", 0)) <= now():
		return "expired"
	var game: Variant = tab.get("game")
	if str(tab.get("status", "")) == "idle" or game == null or str(game).is_empty():
		return "idle"  # rented but no game chosen yet
	if str(tab.get("desired", "")) == "stopped":
		return "stopping" if str(tab.get("status", "")) in ["running", "queued"] else "stopped"
	return str(tab.get("status", "queued"))


static func status_badge(parent: Node, tab: Dictionary) -> PanelContainer:
	var st := display_state(tab)
	return badge(parent, T.status_label(st), T.status_color(st))


static func jar_badge(parent: Node, status: String) -> PanelContainer:
	return badge(parent, T.jar_label(status), T.jar_color(status))


## Decodes PNG or JPEG bytes (detected by magic number). Returns null when neither.
## Money typed by a person: "10.000", "10,000", "1.000.000", "10000", "-5.000" or "10000.0".
## "." / "," are thousands separators only when every group after them has 3 digits; otherwise what follows is
## a fraction and is dropped ("10000.0" → 10000, never 100000). 0 when not a number.
static func parse_vnd(text: String) -> int:
	var s := text.strip_edges().replace(" ", "").replace("đ", "").replace("₫", "")
	var neg := s.begins_with("-")
	if neg or s.begins_with("+"):
		s = s.substr(1)
	var parts := s.replace(",", ".").split(".")
	if parts.size() > 1:
		var thousands := true
		for i in range(1, parts.size()):
			if parts[i].length() != 3:
				thousands = false
		s = "".join(parts) if thousands else parts[0]
	if s.is_empty() or not s.is_valid_int():
		return 0
	return -int(s) if neg else int(s)


static func decode_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 4:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49:
		err = img.load_webp_from_buffer(bytes)
	return img if err == OK else null


## Overflow-menu button: opens native/menu_popup.gd (icons, red danger group, keyboard navigation,
## bottom sheet on narrow windows). Items: [text, Callable] | [text, [Callable, checked]] | null divider;
## an optional 3rd element `false` disables the row.
static func menu_button(parent: Node, text: String, items: Array, variant: String = "GhostButton") -> Button:
	var b := button(parent, text, Callable(), variant)
	b.set_meta("menu_items", items)
	b.pressed.connect(func() -> void: open_menu(b))
	return b


static func open_menu(b: Button) -> Control:
	var MenuPopup: GDScript = load("res://native/menu_popup.gd")
	return MenuPopup.open(b, b.get_meta("menu_items", []))


## "ThuêTab" wordmark: "Thuê" in ink, "Tab" in the accent colour, display font.
static func wordmark(parent: Node, size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var brand := T.brand("name")
	var split := brand.length() - 3 if brand.ends_with("Tab") else brand.length()
	for part in [[brand.left(split), T.color("ink")], [brand.substr(split), T.color("accent")]]:
		if str(part[0]).is_empty():
			continue
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_override("font", AppTheme.font_display_bold)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", part[1])
		row.add_child(l)
	if parent:
		parent.add_child(row)
	return row


## Relative time in Vietnamese: "vừa xong", "5 phút", "3 giờ", "2 ngày", else the date.
static func ago(ts: Variant) -> String:
	if ts == null:
		return ""
	var d := now() - int(ts)
	if d < 60:
		return "vừa xong"
	if d < 3600:
		return "%d phút" % floori(d / 60.0)
	if d < 86400:
		return "%d giờ" % floori(d / 3600.0)
	if d < 7 * 86400:
		return "%d ngày" % floori(d / 86400.0)
	var dt := Time.get_datetime_dict_from_unix_time(int(ts) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d/%02d" % [dt.day, dt.month]
