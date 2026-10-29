extends RefCounted
## Builds the application Theme from design tokens. Widgets select a look via theme_type_variation,
## e.g. "PrimaryButton", "Card", "MutedLabel" — see ui.gd helpers.

const T := preload("res://native/tokens.gd")

const GradientBox := preload("res://native/gradient_box.gd")

static var font_regular: Font
static var font_medium: Font
static var font_bold: Font
static var font_display: Font
static var font_display_bold: Font
static var font_mono: Font


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = -1, pad_x: int = -1, pad_y: int = -1, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	if border.a > 0.0:
		s.set_border_width_all(border_w)
	s.set_corner_radius_all(T.radius("md") if radius < 0 else radius)
	var px := T.space("lg") if pad_x < 0 else pad_x
	var py := T.space("sm") if pad_y < 0 else pad_y
	s.content_margin_left = px
	s.content_margin_right = px
	s.content_margin_top = py
	s.content_margin_bottom = py
	s.anti_aliasing = true
	return s


static func _system(names: PackedStringArray, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = names
	f.font_weight = weight
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


## Bundled TTFs from tokens.font.files (Be Vietnam Pro body, Chakra Petch display); system fallback.
static func _fonts() -> void:
	var body := T.font_names("family")
	font_regular = _or(T.font_file("body_400"), _system(body, 400))
	font_medium = _or(T.font_file("body_500"), _system(body, 500))
	font_bold = _or(T.font_file("body_600"), _system(body, 600))
	font_display = _or(T.font_file("display_600"), font_bold)
	font_display_bold = _or(T.font_file("display_700"), font_display)
	var mono := SystemFont.new()
	var mono_names := T.font_names("mono")
	mono_names.append("monospace")
	mono.font_names = mono_names
	font_mono = mono


static func _or(a: Font, b: Font) -> Font:
	return a if a != null else b


static func _button(theme: Theme, type: String, bg: Color, border: Color, ink: Color, hover_bg: Color, hover_border: Color) -> void:
	if not ClassDB.class_exists(type):
		theme.set_type_variation(type, "Button")
	# Size comes from tokens.components.button (height is applied as the control's minimum size by
	# ui.gd so the label is always vertically centred; vertical padding stays small).
	var pad_x := int(T.compf("button.md.padding_x", 16))
	var pad_y := 4
	var r := int(T.compf("button.md.radius", 10))
	theme.set_stylebox("normal", type, box(bg, border, r, pad_x, pad_y))
	theme.set_stylebox("hover", type, box(hover_bg, hover_border, r, pad_x, pad_y))
	theme.set_stylebox("pressed", type, box(hover_bg.darkened(0.08), hover_border, r, pad_x, pad_y))
	theme.set_stylebox("hover_pressed", type, box(hover_bg.darkened(0.08), hover_border, r, pad_x, pad_y))
	var dis := box(bg, border, r, pad_x, pad_y)
	dis.bg_color.a *= 0.45
	dis.border_color.a *= 0.45
	theme.set_stylebox("disabled", type, dis)
	var focus := box(Color.TRANSPARENT, T.color("accent"), r, pad_x, pad_y, 2)
	focus.draw_center = false
	theme.set_stylebox("focus", type, focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, ink)
	var dim_ink := ink
	dim_ink.a = 0.45
	theme.set_color("font_disabled_color", type, dim_ink)
	theme.set_color("icon_normal_color", type, ink)
	theme.set_color("icon_hover_color", type, ink)
	theme.set_color("icon_pressed_color", type, ink)
	theme.set_font("font", type, font_bold)
	theme.set_constant("h_separation", type, int(T.compf("button.gap", 8)))


static func _label(theme: Theme, type: String, size_key: String, color_key: String, font: Font = null) -> void:
	theme.set_type_variation(type, "Label")
	theme.set_font_size("font_size", type, T.font_size(size_key))
	theme.set_color("font_color", type, T.color(color_key))
	if font:
		theme.set_font("font", type, font)


static func _panel(theme: Theme, type: String, style: StyleBox) -> void:
	theme.set_type_variation(type, "PanelContainer")
	theme.set_stylebox("panel", type, style)


static func build() -> Theme:
	T.ensure_loaded()
	_fonts()
	var theme := Theme.new()
	var ink := T.color("ink")
	var muted := T.color("muted")
	var dim := T.color("dim")
	var surface := T.color("surface")
	var surface_2 := T.color("surface_2")
	var border := T.color("border")
	var accent := T.color("accent")
	var danger := T.color("danger")

	theme.default_font = font_regular
	theme.default_font_size = T.font_size("md")

	# Labels
	theme.set_color("font_color", "Label", ink)
	_label(theme, "HeroLabel", "hero", "ink", font_display_bold)
	_label(theme, "TitleLabel", "xxl", "ink", font_display_bold)
	_label(theme, "HeadingLabel", "xl", "ink", font_display_bold)
	_label(theme, "SubheadingLabel", "lg", "ink", font_display)
	_label(theme, "StrongLabel", "md", "ink", font_bold)
	_label(theme, "MutedLabel", "sm", "muted")
	_label(theme, "BodyMutedLabel", "md", "muted")
	_label(theme, "DimLabel", "xs", "dim")
	_label(theme, "CaptionLabel", "xs", "muted", font_bold)
	_label(theme, "AccentLabel", "md", "accent_2", font_display_bold)
	_label(theme, "DangerLabel", "sm", "danger")
	_label(theme, "StatLabel", "xxl", "ink", font_display_bold)
	theme.set_constant("line_spacing", "Label", 3)  # room for stacked Vietnamese diacritics
	theme.set_type_variation("MonoLabel", "Label")
	theme.set_font("font", "MonoLabel", font_mono)
	theme.set_font_size("font_size", "MonoLabel", T.font_size("sm"))
	theme.set_color("font_color", "MonoLabel", muted)

	# Buttons
	_button(theme, "Button", surface_2, border, ink, surface_2.lightened(0.06), muted.darkened(0.3))
	_button(theme, "PrimaryButton", accent, accent, T.color("accent_ink"), accent.lightened(0.12), accent.lightened(0.12))
	var grad := T.gradient()
	var glow := Color(grad[0], float(T.effect("glow_alpha", 0.35)))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var g: StyleBox = GradientBox.new()
		g.set("color_from", grad[0])
		g.set("color_to", grad[1])
		g.set("radius", T.compf("button.md.radius", 10))
		g.set("glow_color", glow if state in ["normal", "hover"] else Color.TRANSPARENT)
		g.set("glow_size", 10.0 if state == "hover" else 6.0)
		g.set("brightness", 1.12 if state == "hover" else (0.85 if state.contains("pressed") else 1.0))
		if state == "disabled":
			g.set("color_from", Color(grad[0], 0.35))
			g.set("color_to", Color(grad[1], 0.35))
		g.content_margin_left = T.compf("button.md.padding_x", 16)
		g.content_margin_right = T.compf("button.md.padding_x", 16)
		g.content_margin_top = 4
		g.content_margin_bottom = 4
		theme.set_stylebox(state, "PrimaryButton", g)
	theme.set_font("font", "PrimaryButton", font_bold)
	var danger_soft := danger
	danger_soft.a = 0.14
	var danger_hover := danger
	danger_hover.a = 0.26
	_button(theme, "DangerButton", danger_soft, danger.darkened(0.25), danger.lightened(0.25), danger_hover, danger)
	_button(theme, "GhostButton", Color.TRANSPARENT, Color.TRANSPARENT, muted, surface_2, Color.TRANSPARENT)
	theme.set_color("font_hover_color", "GhostButton", ink)
	_button(theme, "NavButton", Color.TRANSPARENT, Color.TRANSPARENT, muted, surface_2, Color.TRANSPARENT)
	theme.set_color("font_hover_color", "NavButton", ink)
	theme.set_constant("h_separation", "NavButton", T.space("md"))
	_button(theme, "NavButtonActive", T.color("accent_soft"), Color(accent, 0.45), T.accent_text(), T.color("accent_soft"), Color(accent, 0.45))
	theme.set_constant("h_separation", "NavButtonActive", T.space("md"))
	_button(theme, "ChipButton", Color.TRANSPARENT, border, muted, surface_2, border)
	_button(theme, "ChipButtonActive", T.color("accent_soft"), accent, T.accent_text(), T.color("accent_soft"), T.color("accent_2"))
	# Rows of the custom overflow menu (menu_popup.gd): flat, highlighted on hover/keyboard focus.
	theme.set_type_variation("MenuItem", "Button")
	var mi_r := int(T.radius("sm"))
	theme.set_stylebox("normal", "MenuItem", box(Color.TRANSPARENT, Color.TRANSPARENT, mi_r, 0, 0))
	theme.set_stylebox("disabled", "MenuItem", box(Color.TRANSPARENT, Color.TRANSPARENT, mi_r, 0, 0))
	for st in ["hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(st, "MenuItem", box(T.color("accent_soft"), Color.TRANSPARENT, mi_r, 0, 0))
	_button(theme, "KeyButton", surface_2, border, ink, border, T.color("accent_2"))
	theme.set_font_size("font_size", "KeyButton", T.font_size("lg"))
	theme.set_font("font", "KeyButton", font_display_bold)
	for t in ["NavButton", "NavButtonActive"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var sb: StyleBoxFlat = theme.get_stylebox(state, t)
			sb.content_margin_top = T.space("sm") + 2
			sb.content_margin_bottom = T.space("sm") + 2
			sb.content_margin_left = T.space("md")
	theme.set_type_variation("BottomNavButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		theme.set_stylebox(state, "BottomNavButton", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 6))
	var bfocus := StyleBoxEmpty.new()
	theme.set_stylebox("focus", "BottomNavButton", bfocus)
	theme.set_font_size("font_size", "BottomNavButton", T.font_size("xs"))
	theme.set_color("font_color", "BottomNavButton", dim)
	theme.set_color("font_hover_color", "BottomNavButton", ink)
	theme.set_color("font_pressed_color", "BottomNavButton", accent)
	theme.set_color("icon_normal_color", "BottomNavButton", dim)
	theme.set_type_variation("BottomNavButtonActive", "BottomNavButton")
	theme.set_color("font_color", "BottomNavButtonActive", accent)
	theme.set_color("font_hover_color", "BottomNavButtonActive", accent)
	theme.set_font("font", "BottomNavButtonActive", font_bold)

	# Panels
	theme.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	var glass := Color(surface, float(T.effect("glass_alpha", 0.85)))
	var card_r := int(T.compf("card.radius", 16))
	var card_p := int(T.compf("card.padding", 16))
	_panel(theme, "Card", box(glass, border, card_r, card_p, card_p))
	var live := box(glass, Color(T.color("success"), 0.75), card_r, card_p, card_p)
	live.shadow_color = Color(T.color("success"), float(T.effect("glow_alpha", 0.35)) * 0.6)
	live.shadow_size = 14
	_panel(theme, "CardLive", live)
	var card_pl := int(T.compf("card.padding_lg", 20))
	var hl := box(glass, Color(accent, 0.8), card_r, card_pl, card_pl)
	_panel(theme, "CardAccent", hl)
	var console := box(Color("#05060c"), Color(accent, 0.7), T.radius("lg") + 6, T.space("md"), T.space("md"), 2)
	console.shadow_color = Color(T.color("accent_2"), float(T.effect("glow_alpha", 0.35)) * 0.5)
	console.shadow_size = 18
	_panel(theme, "Console", console)
	_panel(theme, "CardInset", box(surface_2, border, T.radius("md"), T.space("md"), T.space("md")))
	_panel(theme, "Screen", box(T.color("screen"), Color.TRANSPARENT, T.radius("sm"), 0, 0))
	var side := box(surface, border, 0, T.space("md"), T.space("lg"))
	side.border_width_top = 0
	side.border_width_bottom = 0
	side.border_width_left = 0
	side.bg_color = Color(surface, 0.9)
	_panel(theme, "Sidebar", side)
	var header := box(Color(T.color("bg"), 0.82), border, 0, T.space("xl"), T.space("md"))
	header.border_width_top = 0
	header.border_width_left = 0
	header.border_width_right = 0
	_panel(theme, "Header", header)
	var bottom := box(surface, border, 0, T.space("xs"), T.space("xs"))
	bottom.border_width_bottom = 0
	bottom.border_width_left = 0
	bottom.border_width_right = 0
	_panel(theme, "BottomNav", bottom)
	var overlay := StyleBoxFlat.new()
	overlay.bg_color = Color(0, 0, 0, 0.62)
	_panel(theme, "Overlay", overlay)
	var toast := box(surface_2, border, int(T.compf("toast.radius", 12)), T.space("md"), T.space("sm"))
	var shade := 0.4 if T.mode == "dark" else 0.14  # softer elevation on the light palette
	toast.shadow_color = Color(0, 0, 0, shade)
	toast.shadow_size = 12
	_panel(theme, "Toast", toast)
	var dp := int(T.compf("dialog.padding", 24))
	var modal := box(surface, border, int(T.compf("dialog.radius", 16)), dp, dp)
	modal.shadow_color = Color(0, 0, 0, shade + 0.05)
	modal.shadow_size = 24
	_panel(theme, "Modal", modal)

	# Inputs
	var in_r := int(T.compf("input.radius", 10))
	var in_p := int(T.compf("input.padding_x", 12))
	var field := box(T.color("bg"), border, in_r, in_p, 6)
	var field_focus := box(T.color("bg"), accent, in_r, in_p, 6)
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, field)
		theme.set_stylebox("focus", type, field_focus)
		theme.set_stylebox("read_only", type, box(surface_2, border, in_r, in_p, 6))
		theme.set_font_size("font_size", type, int(T.compf("input.font", 14)))
		theme.set_color("font_color", type, ink)
		theme.set_color("font_readonly_color", type, muted)
		theme.set_color("font_placeholder_color", type, dim)
		theme.set_color("caret_color", type, accent)
		theme.set_color("selection_color", type, T.color("accent_soft"))
	theme.set_font("font", "TextEdit", font_mono)
	theme.set_font_size("font_size", "TextEdit", T.font_size("sm"))
	theme.set_stylebox("focus", "TextEdit", field)

	_button(theme, "OptionButton", T.color("bg"), border, ink, surface_2, muted.darkened(0.3))
	theme.set_font("font", "OptionButton", font_regular)
	theme.set_constant("arrow_margin", "OptionButton", T.space("md"))

	# Checkbox
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, T.radius("sm"), 4, 4))
	theme.set_color("font_color", "CheckBox", ink)
	theme.set_color("font_hover_color", "CheckBox", ink)
	theme.set_color("font_pressed_color", "CheckBox", ink)
	theme.set_color("font_hover_pressed_color", "CheckBox", ink)
	theme.set_color("font_focus_color", "CheckBox", ink)
	theme.set_constant("h_separation", "CheckBox", T.space("sm"))
	theme.set_icon("checked", "CheckBox", _check_icon(true, accent, muted))
	theme.set_icon("unchecked", "CheckBox", _check_icon(false, accent, muted))
	theme.set_icon("checked_disabled", "CheckBox", _check_icon(true, Color(accent, 0.4), dim))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, accent, Color(dim, 0.5)))

	# Popup menus (OptionButton dropdowns)
	var menu_r := int(T.compf("popover.menu.radius", 12))
	var pm := box(surface_2, border, menu_r, 6, 6)
	pm.shadow_color = Color(0, 0, 0, 0.35 if T.mode == "dark" else 0.14)
	pm.shadow_size = 12
	theme.set_stylebox("panel", "PopupMenu", pm)
	theme.set_stylebox("hover", "PopupMenu", box(T.color("accent_soft"), Color.TRANSPARENT, T.radius("sm"), T.space("sm"), 0))
	theme.set_color("font_color", "PopupMenu", ink)
	theme.set_color("font_hover_color", "PopupMenu", accent)
	theme.set_color("font_disabled_color", "PopupMenu", dim)
	theme.set_color("font_separator_color", "PopupMenu", dim)
	# Item height = tokens popover.menu.item_height: font line height + separation.
	var line_h := font_regular.get_height(T.font_size("md"))
	theme.set_constant("v_separation", "PopupMenu", maxi(4, int(T.compf("popover.menu.item_height", 40) - line_h)))
	theme.set_constant("icon_max_width", "PopupMenu", int(T.compf("popover.menu.icon", 18)))
	theme.set_constant("h_separation", "PopupMenu", int(T.compf("button.gap", 8)))
	theme.set_constant("item_start_padding", "PopupMenu", T.space("md"))
	theme.set_constant("item_end_padding", "PopupMenu", T.space("md"))

	# Scrollbars: thin and quiet
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color.TRANSPARENT
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		var grab := box(border, Color.TRANSPARENT, T.radius("pill"), 3, 3)
		theme.set_stylebox("grabber", type, grab)
		theme.set_stylebox("grabber_highlight", type, box(dim, Color.TRANSPARENT, T.radius("pill"), 3, 3))
		theme.set_stylebox("grabber_pressed", type, box(muted, Color.TRANSPARENT, T.radius("pill"), 3, 3))

	theme.set_stylebox("panel", "TooltipPanel", box(surface_2, border, T.radius("sm"), T.space("sm"), T.space("xs")))
	theme.set_color("font_color", "TooltipLabel", ink)
	theme.set_stylebox("separator", "HSeparator", _line(border))
	theme.set_constant("separation", "HSeparator", 1)
	return theme


## 18 px checkbox icon drawn at 3× and downscaled for smooth edges.
static func _check_icon(checked: bool, fill: Color, edge: Color) -> ImageTexture:
	var n := 54
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := 12.0
	var a := Vector2(14, 28)
	var m := Vector2(23, 37)
	var b := Vector2(40, 18)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := Vector2(maxf(absf(p.x - n / 2.0) - (n / 2.0 - 3.0 - r), 0.0), maxf(absf(p.y - n / 2.0) - (n / 2.0 - 3.0 - r), 0.0))
			var d := q.length() - r  # signed distance to the rounded square
			var c := Color.TRANSPARENT
			if checked:
				if d <= 0.0:
					c = fill
					if Geometry2D.get_closest_point_to_segment(p, a, m).distance_to(p) < 3.6 or Geometry2D.get_closest_point_to_segment(p, m, b).distance_to(p) < 3.6:
						c = Color.WHITE
			elif d <= 0.0 and d > -5.0:
				c = edge
			img.set_pixel(x, y, c)
	img.resize(18, 18, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _line(c: Color) -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = c
	l.thickness = 1
	return l
