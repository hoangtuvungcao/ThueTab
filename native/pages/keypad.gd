extends RefCounted
## Nokia-style keypad shared by the single viewer and the multi-screen wall.
## Codes are the API key names: Up Down Left Right Return Escape space BackSpace F1 F2 asterisk numbersign 0–9.

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")

const KEYMAP := {
	KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right",
	KEY_ENTER: "Return", KEY_KP_ENTER: "Return", KEY_ESCAPE: "Escape", KEY_SPACE: "space",
	KEY_BACKSPACE: "BackSpace", KEY_F1: "F1", KEY_F2: "F2",
	KEY_ASTERISK: "asterisk", KEY_KP_MULTIPLY: "asterisk", KEY_NUMBERSIGN: "numbersign",
}


static func code_for_event(event: InputEvent) -> String:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return ""
	# Shifted digits on US layouts: Shift+8 = *, Shift+3 = #
	if k.unicode == 42:
		return "asterisk"
	if k.unicode == 35:
		return "numbersign"
	if KEYMAP.has(k.keycode):
		return KEYMAP[k.keycode]
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		return str(k.keycode - KEY_0)
	if k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
		return str(k.keycode - KEY_KP_0)
	return ""


static func _key(parent: Node, text: String, code: String, send: Callable, variant: String = "KeyButton", h: float = 42.0) -> Button:
	var b := UI.button(parent, text, func() -> void: send.call(code), variant)
	b.set_meta("instant", true)
	b.custom_minimum_size = Vector2(0, UI.target_h(h))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = code
	return b


static func _grid(parent: Node, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", T.space("sm"))
	g.add_theme_constant_override("v_separation", T.space("sm"))
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


## Builds soft keys, d-pad with OK, clear/back, and the 12-key numeric pad.
## with_soft=false when the caller places the soft keys itself (viewer puts them under the screen).
## size_key = user pref keypad_size (sm/md/lg); "" keeps the default for the context (`small`).
## Returns every key Button (row by row, 8 rows) so the caller can resize them to fit the window.
static func build(parent: Node, send: Callable, small: bool = false, with_soft: bool = true, size_key: String = "") -> Array:
	var h: float = {"sm": 36.0, "md": 42.0, "lg": 54.0}.get(size_key, 36.0 if small else 42.0)
	var keys: Array = []
	var soft := _grid(parent, 3)
	if with_soft:
		keys.append(_key(soft, "Mềm trái", "F1", send, "", h))
	keys.append(_key(soft, "Xóa (C)", "BackSpace", send, "", h))
	if not with_soft:
		soft.columns = 1
	else:
		keys.append(_key(soft, "Mềm phải", "F2", send, "", h))

	var dpad := _grid(parent, 3)
	for k in [["Esc", "Escape"], ["▲", "Up"], ["Space", "space"], ["◀", "Left"], ["OK", "Return"], ["▶", "Right"]]:
		keys.append(_key(dpad, k[0], k[1], send, "PrimaryButton" if k[1] == "Return" else ("" if k[1] in ["Escape", "space"] else "KeyButton"), h))
	var gap1 := Control.new()
	dpad.add_child(gap1)
	keys.append(_key(dpad, "▼", "Down", send, "KeyButton", h))
	var gap2 := Control.new()
	dpad.add_child(gap2)

	var pad := _grid(parent, 3)
	for k in [["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"], ["6", "6"], ["7", "7"], ["8", "8"], ["9", "9"], ["*", "asterisk"], ["0", "0"], ["#", "numbersign"]]:
		var b := _key(pad, k[0], k[1], send, "KeyButton", h)
		keys.append(b)
		if k[0] == "*":
			b.add_theme_font_size_override("font_size", T.font_size("xxl"))

	return keys
