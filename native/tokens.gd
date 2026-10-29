extends RefCounted
## Design tokens loaded at runtime from res://design/tokens.json (shared with the web client).
## Everything visual (colors, radius, spacing, font sizes, status labels, nav, poll intervals) comes from here.

const PATH := "res://design/tokens.json"

static var data: Dictionary = {}
static var mode: String = "dark"  # resolved palette: "dark" | "light"
static var accent_id: String = "neon"  # tokens.accents preset chosen in user prefs
static var large: bool = false  # phone layout: body text +1–2 px for readability
static var font_scale: float = 1.0  # user pref font_scale / 100
static var dense: bool = false  # user pref density=compact: tighter spacing


static func ensure_loaded() -> void:
	if not data.is_empty():
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("Không đọc được %s" % PATH)
		data = {"color": {"dark": {}}}


static func color(key: String) -> Color:
	ensure_loaded()
	var preset: Dictionary = data.get("accents", {}).get(accent_id, {})
	if key in ["accent", "accent_2"] and preset.has(key):
		var c := Color(str(preset[key]))
		return c.darkened(0.18) if mode == "light" else c
	if key == "accent_ink" and preset.has("accent"):
		return Color("#03141f") if color("accent").get_luminance() > 0.5 else Color.WHITE
	if key == "accent_soft" and preset.has("accent"):
		return Color(color("accent"), 0.15 if mode == "dark" else 0.12)
	var palette: Dictionary = data.get("color", {}).get(mode, {})
	var value: String = str(palette.get(key, "#ff00ff"))
	return Color(value)


static func space(key: String) -> int:
	ensure_loaded()
	var v := int(data.get("space", {}).get(key, 8))
	return maxi(2, int(round(v * 0.75))) if dense and v >= 12 else v


static func radius(key: String) -> int:
	ensure_loaded()
	return int(data.get("radius", {}).get(key, 8))


static func font_size(key: String) -> int:
	ensure_loaded()
	var v := int(data.get("font", {}).get("size", {}).get(key, 14))
	if large and v <= 16:
		v += 2 if v <= 13 else 1
	return maxi(11, int(round(v * font_scale)))


static func font_names(key: String) -> PackedStringArray:
	## Parses a CSS font stack ("Inter, system-ui, 'Segoe UI'") into SystemFont names.
	ensure_loaded()
	var names := PackedStringArray()
	for part in str(data.get("font", {}).get(key, "")).split(","):
		var n := part.strip_edges().trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
		if n.is_empty() or n in ["system-ui", "-apple-system", "ui-monospace"]:
			continue
		names.append(n)
	return names


static func poll(key: String) -> float:
	ensure_loaded()
	return float(data.get("poll_seconds", {}).get(key, 4))


static func nav() -> Array:
	ensure_loaded()
	return data.get("nav", [])


static func brand(key: String) -> String:
	ensure_loaded()
	return str(data.get("brand", {}).get(key, ""))


static func status_label(state: String) -> String:
	ensure_loaded()
	return str(data.get("status", {}).get(state, {}).get("label", state))


static func status_color(state: String) -> Color:
	ensure_loaded()
	return color(str(data.get("status", {}).get(state, {}).get("color", "muted")))


static func jar_label(state: String) -> String:
	ensure_loaded()
	return str(data.get("jar_status", {}).get(state, {}).get("label", state))


static func jar_color(state: String) -> Color:
	ensure_loaded()
	return color(str(data.get("jar_status", {}).get(state, {}).get("color", "muted")))


static func effect(key: String, default: Variant = null) -> Variant:
	ensure_loaded()
	return data.get("effects", {}).get(key, default)


static func gradient() -> Array:
	return [color("accent"), color("accent_2")]


static func accents() -> Dictionary:
	ensure_loaded()
	return data.get("accents", {})


## Loads a font file listed in tokens.font.files (paths relative to res://design/). Null if missing.
static func font_file(key: String) -> FontFile:
	ensure_loaded()
	var rel := str(data.get("font", {}).get("files", {}).get(key, ""))
	if rel.is_empty():
		return null
	var path := "res://design/" + rel
	if not FileAccess.file_exists(path):
		return null
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return null
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.hinting = TextServer.HINTING_LIGHT
	return f


static func stream(key: String, default: Variant = null) -> Variant:
	ensure_loaded()
	return data.get("stream", {}).get(key, default)


static func order_label(state: String) -> String:
	ensure_loaded()
	return str(data.get("order_status", {}).get(state, {}).get("label", state))


static func order_color(state: String) -> Color:
	ensure_loaded()
	return color(str(data.get("order_status", {}).get(state, {}).get("color", "muted")))


static func user_menu() -> Array:
	ensure_loaded()
	return data.get("user_menu", [])


## Accent colour for text/icons on tinted backgrounds: brighter on dark, deeper on light.
static func accent_text() -> Color:
	return color("accent").lightened(0.3) if mode == "dark" else color("accent").darkened(0.25)


## tokens.components lookup by dotted path, e.g. comp("button.md.height", 40).
static func comp(path: String, default: Variant = null) -> Variant:
	ensure_loaded()
	var node: Variant = data.get("components", {})
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default
	return node


static func compf(path: String, default: float) -> float:
	return float(comp(path, default))
