extends Control
## ThuêTab native client — app shell.
## Owns shared state (config/user/tabs/…), polling timers, responsive layout (sidebar on wide windows,
## bottom bar on narrow/portrait), modal + toast layers. Each page lives in native/pages/.

const T := preload("res://native/tokens.gd")
const AppTheme := preload("res://native/theme.gd")
const UI := preload("res://native/ui.gd")
const Api := preload("res://native/api.gd")
const QA := preload("res://native/qa.gd")

const PAGES := {
	"login": preload("res://native/pages/login.gd"),
	"tabs": preload("res://native/pages/tabs.gd"),
	"viewer": preload("res://native/pages/viewer.gd"),
	"jars": preload("res://native/pages/jars.gd"),
	"wallet": preload("res://native/pages/wallet.gd"),
	"plans": preload("res://native/pages/plans.gd"),
	"help": preload("res://native/pages/help.gd"),
	"admin": preload("res://native/pages/admin.gd"),
	"account": preload("res://native/pages/account.gd"),
	"wall": preload("res://native/pages/wall.gd"),
	"settings": preload("res://native/pages/settings.gd"),
	"support": preload("res://native/pages/support.gd"),
	"referral": preload("res://native/pages/referral.gd"),
}
## App pages reachable from the account menu that tokens.user_menu does not list (yet).
const EXTRA_MENU := [
	{"id": "support", "label": "Hỗ trợ", "icon": "life-buoy"},
	{"id": "referral", "label": "Giới thiệu bạn bè", "icon": "user"},
]
const PREF_DEFAULTS := {
	"theme": "dark", "accent": "neon", "font_scale": 100, "density": "comfortable", "reduce_motion": false,
	"default_fps": 30, "show_fps": true, "keypad_size": "md", "haptics": true, "sounds": false,
	"default_screen": "240x320", "start_page": "tabs", "wall_columns": "auto", "expiry_alert_hours": 24,
}
const APP_ICON := preload("res://native/icons/app_icon.png")
const SETTINGS_PATH := "user://settings.cfg"
const CLIENT_CONFIG := "res://native/client.json"  # {"api_url": ...} — edited by the operator before export
const COMPACT_WIDTH := 760.0  # narrower → phone layout (bottom bar, large text, 48 px targets)
const COMPACT_HEIGHT := 520.0  # shorter (phone landscape) → phone layout too
const MAX_CONTENT := 1240.0  # comfortable reading width on wide desktop windows
const FADE := 0.18

signal data_refreshed

var api: Node
var config: Dictionary = {}
var server: Dictionary = {}
var user: Dictionary = {}
var tabs: Array = []
var slots: Array = []
var jars: Array = []
var wallet: Dictionary = {}
var admin: Dictionary = {}

var page_id: String = ""
var page_params: Dictionary = {}
var page: Node
var compact: bool = false
var refreshing: bool = false
var persist: bool = true  # QA runs set this false so the saved login is untouched
var _pending_jars: int = -1
var _qa: RefCounted
var _refresh_again: bool = false
var prefs: Dictionary = {}  # per-device UI preferences (e.g. stream FPS), saved with the token
var remember: bool = true  # "Ghi nhớ đăng nhập": persist the session token on this device
var thumbs: Node  # shared live thumbnail feed (thumb_feed.gd)
var immersive: bool = false
var pref_override: Dictionary = {}  # device-local overrides applied on top of account prefs (QA/preview)
var motion: bool = true  # false when the user enabled reduce_motion: no tweens
var _look_sig: String = ""  # visual prefs currently applied to the Theme
var _backdrop: Control
var _announce: PanelContainer
var _announce_label: Label
var _click: AudioStreamPlayer
var _brand_box: HBoxContainer
var page_overlay: Control
var notifications: Dictionary = {"unread": 0, "items": []}
var _maint: PanelContainer
var _maint_label: Label

var _login_layer: Control
var _shell: HBoxContainer
var _sidebar: PanelContainer
var _side_nav: VBoxContainer
var _side_footer: VBoxContainer
var _header_title: Label
var _header_right: HBoxContainer
var _header_brand: Control
var _header: PanelContainer
var _offline: PanelContainer
var _scroll: ScrollContainer
var _page_margin: MarginContainer
var _bottom_nav: PanelContainer
var _bottom_row: HBoxContainer
var _overlay: PanelContainer
var _modal_body: VBoxContainer
var _modal_scroll: ScrollContainer
var _modal_footer: HBoxContainer  # sticky action row below the scrolling dialog body
var _modal_panel: PanelContainer
var _toast_layer: Control
var _busy_bar: Control
var _busy_tween: Tween
var _toasts: Array = []  # live toast panels, newest last
var _modal_head: HBoxContainer
var _modal_title: Label
var _sheet_handle: Control
var _modal_dim: ColorRect
var _modal_width: float = 560.0
var _sheet_offset: float = 0.0  # slide-in offset for bottom sheets (animated, applied by _layout_modal)
var _kb_h: float = 0.0  # on-screen keyboard height in UI units: dialogs sit above it ("Gõ chữ vào game")
var _kb_top := false  # typing in a dialog, keyboard height unknown by any means: dialog goes to the top
var _ime_view: Variant = null  # Android decor view, read for the keyboard (IME) inset; false = not available
var _pop_layer: Control  # notifications popover (desktop)
var _bell: Button
var _retired: Array = []
var _last_width: float = -1.0
var _modal_tween: Tween
var _insets := Rect2()  # safe-area insets (left, top, right, bottom) in canvas units


func _ready() -> void:
	T.ensure_loaded()
	Engine.max_fps = 0  # uncapped; vsync paces rendering so the 60 fps stream is never throttled
	theme = AppTheme.build()
	_setup_window()

	api = Api.new()
	api.name = "Api"
	add_child(api)
	add_child(preload("res://native/drag_scroll.gd").new())
	api.unauthorized.connect(_on_unauthorized)
	api.connectivity.connect(_on_connectivity)
	_load_settings()
	thumbs = preload("res://native/thumb_feed.gd").new()
	thumbs.api = api
	add_child(thumbs)

	_backdrop = preload("res://native/backdrop.gd").new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_click = AudioStreamPlayer.new()
	_click.stream = _make_click()
	_click.volume_db = -14.0
	add_child(_click)

	_build_shell()
	_build_layers()
	_start_timers()
	resized.connect(_on_resized)
	_on_resized.call_deferred()

	if QA.requested():
		_qa = QA.new()  # keep a reference: a RefCounted coroutine dies with its last reference
		_qa.run(self)
		return
	_boot()


func _setup_window() -> void:
	# Responsive layout instead of uniform stretching: 1 canvas unit = 1 logical pixel (× DPI scale).
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var factor := 1.0
	if OS.has_feature("mobile"):
		factor = clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 4.0)
	else:
		factor = clampf(DisplayServer.screen_get_scale(), 1.0, 3.0)
		win.min_size = Vector2i(360, 360)
	win.content_scale_factor = factor


func _boot() -> void:
	await load_public()
	if api.token.is_empty():
		go("login")
		return
	var saved_token: String = api.token
	var me: Dictionary = await api.request("/me")
	if me.ok:
		user = me.data
		await enter_app()
	elif me.code == 0:
		# Offline: keep the saved session; the login screen shows the network message with "Thử lại".
		api.token = ""
		go("login")
		api.token = saved_token
	else:
		api.token = ""
		save_settings()
		go("login")
		if me.code != 401:
			toast(me.error, true)


# ---------------- settings ----------------

## API base URL: bundled res://native/client.json, overridable only by the `--api=URL` user arg (QA).
## Public web address for links people open in a browser (share, referral). The API host has no web pages.
func web_url() -> String:
	var w := str(config.get("web_url", "")).strip_edges().trim_suffix("/")
	return w if w.begins_with("http") else str(api.endpoint)


func _load_endpoint() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--api="):
			return a.trim_prefix("--api=").strip_edges().trim_suffix("/")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLIENT_CONFIG))
	if parsed is Dictionary and str(parsed.get("api_url", "")) != "":
		return str(parsed.api_url).strip_edges().trim_suffix("/")
	push_error("Thiếu api_url trong " + CLIENT_CONFIG)
	return "http://127.0.0.1:8000"


func _load_settings() -> void:
	api.endpoint = _load_endpoint()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		api.token = str(cfg.get_value("auth", "token", ""))
		if cfg.has_section("prefs"):
			for k in cfg.get_section_keys("prefs"):
				prefs[k] = cfg.get_value("prefs", k)


func pref(key: String, default: Variant) -> Variant:
	return prefs.get(key, default)


func set_pref(key: String, value: Variant) -> void:
	prefs[key] = value
	save_settings()


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", api.token if remember else "")
	for k in prefs:
		cfg.set_value("prefs", k, prefs[k])
	cfg.save(SETTINGS_PATH)


# ---------------- data ----------------

## Config + public server status (no auth needed).
func load_public() -> void:
	var c: Dictionary = await api.request("/config")
	if c.ok:
		config = c.data
		_render_announcement()
	await load_status()


func load_status() -> void:
	var s: Dictionary = await api.request("/status", Api.GET, null, 8.0)
	if s.ok:
		server = s.data
		_render_sidebar_footer()
	if not api.token.is_empty() and page_id != "login":
		var c: Dictionary = await api.request("/config")
		if c.ok:
			config = c.data
			_render_announcement()
		await load_notifications()


func load_notifications() -> void:
	var r: Dictionary = await api.request("/notifications")
	if r.ok and r.data is Dictionary:
		var changed := int(r.data.get("unread", 0)) != int(notifications.get("unread", 0))
		notifications = r.data
		if changed:
			_render_header()


func enter_app() -> void:
	apply_prefs()
	_rebuild_nav()
	_shell.visible = true
	_login_layer.visible = false
	await refresh(true)
	var start := str(uprefs().get("start_page", "tabs"))
	go(start if PAGES.has(start) and start != "login" else "tabs")


# ---------------- user preferences (synced with the web via /me/prefs) ----------------

func uprefs() -> Dictionary:
	var p: Dictionary = PREF_DEFAULTS.duplicate()
	var server_prefs: Variant = user.get("prefs", {})
	if server_prefs is Dictionary:
		p.merge(server_prefs, true)
	p.merge(pref_override, true)
	return p


## Save one preference: applied immediately (optimistic), then PATCH /me/prefs; reverted on error.
func set_user_pref(key: String, value: Variant) -> void:
	var before: Dictionary = uprefs()
	var p: Dictionary = user.get("prefs", {}) if user.get("prefs") is Dictionary else {}
	p[key] = value
	user["prefs"] = p
	apply_prefs()
	var r: Dictionary = await api.request("/me/prefs", Api.PATCH, {key: value})
	if r.ok and r.data is Dictionary and r.data.has("prefs"):
		user["prefs"] = r.data.prefs
	elif not r.ok:
		user["prefs"] = before
		apply_prefs()
		toast(r.error, true)


## Applies visual prefs (theme, accent, text size, density, motion). Rebuilds the Theme and current page
## only when something visual actually changed.
func apply_prefs() -> void:
	var p := uprefs()
	var theme_pref := str(p.theme)
	var mode := theme_pref
	if theme_pref == "system":
		mode = "dark" if (not DisplayServer.is_dark_mode_supported() or DisplayServer.is_dark_mode()) else "light"
	motion = not bool(p.reduce_motion)
	var sig := JSON.stringify([mode, p.accent, p.font_scale, p.density, compact])
	if sig == _look_sig:
		return
	var only_layout := _look_sig == JSON.stringify([mode, p.accent, p.font_scale, p.density, not compact])
	_look_sig = sig
	T.mode = mode
	T.accent_id = str(p.accent)
	T.font_scale = float(p.font_scale) / 100.0
	T.dense = str(p.density) == "compact"
	T.large = compact
	UI.touch = compact
	theme = AppTheme.build()
	_backdrop.queue_redraw()
	_apply_layout()
	_render_header()
	_rebuild_nav()
	_render_sidebar_footer()
	_render_brand()
	_restyle_banners()
	if page_id == "viewer" and only_layout and page:
		page.on_resize()  # phone ↔ desktop layout switch: keep the live stream connected
	elif not page_id.is_empty():
		go(page_id, page_params)


## Key feedback for the Nokia keypad: haptics on phones, optional click sound.
func key_feedback() -> void:
	var p := uprefs()
	if bool(p.haptics) and OS.has_feature("mobile"):
		Input.vibrate_handheld(15)
	if bool(p.sounds):
		_click.play()


static func _make_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.025)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / n
		var v := int(sin(TAU * 1800.0 * i / rate) * env * 9000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## Refresh shared data. Always /me + /tabs; other collections when the current page needs them (or full).
func refresh(full: bool = false) -> void:
	if api.token.is_empty():
		return
	if refreshing and not full:
		_refresh_again = true  # e.g. user navigated mid-refresh: fetch the new page's data right after
		return
	refreshing = true
	var for_page := page
	if full and config.is_empty():
		await load_public()
	var needs: Array = ["slots", "jars", "wallet"] if full else []
	if page and page.has_method("needs"):
		needs.append_array(page.needs())
	var r: Dictionary = await api.request("/me")
	if r.ok:
		user = r.data
		apply_prefs()  # picks up changes made on the web
	r = await api.request("/tabs")
	if r.ok:
		tabs = r.data
	if "slots" in needs:
		r = await api.request("/slots")
		if r.ok:
			slots = r.data
	if "jars" in needs:
		r = await api.request("/jars")
		if r.ok:
			jars = r.data
	if "wallet" in needs:
		r = await api.request("/wallet")
		if r.ok:
			wallet = r.data
	if "admin" in needs and is_admin():
		r = await api.request("/admin/overview")
		if r.ok:
			admin = r.data
			var pending := int(admin.get("stats", {}).get("pending_jars", 0))
			if pending != _pending_jars:
				_pending_jars = pending
				_rebuild_nav()
	refreshing = false
	if api.token.is_empty():
		return
	_render_header()
	if page and page.has_method("on_data"):
		var keep := _scroll.scroll_vertical
		page.on_data()
		if page == for_page:
			await get_tree().process_frame
			_scroll.scroll_vertical = keep
	data_refreshed.emit()
	if _refresh_again:
		_refresh_again = false
		refresh()


## Perform a mutating API call, toast the result, refresh data. Returns the API result.
func act(path: String, method: int, data: Variant = null, success: String = "") -> Dictionary:
	var r: Dictionary = await api.request(path, method, data)
	if r.ok:
		if not success.is_empty():
			toast(success)
	else:
		toast(r.error, true)
	await refresh(true)
	return r


func is_admin() -> bool:
	return str(user.get("role", "")) == "admin"


func game(id: String) -> Dictionary:
	for g in config.get("games", []):
		if g.get("id") == id:
			return g
	return {"id": id, "name": id, "icon": "custom", "enabled": false}


func plan(id: String) -> Dictionary:
	for p in config.get("plans", []):
		if p.get("id") == id:
			return p
	return {"id": id, "name": "Dùng thử" if id == "trial" else id, "days": 0, "price": 0}


## "midp" (J2ME) / "jar" (Java PC) for tabs running an uploaded JAR, "" for catalog games.
func tab_kind(tab: Dictionary) -> String:
	var jid: Variant = tab.get("custom_jar_id")
	if jid == null or str(jid).is_empty():
		return ""
	for j in jars:
		if str(j.id) == str(jid):
			return str(j.get("kind", ""))
	for j in admin.get("jars", []):
		if str(j.id) == str(jid):
			return str(j.get("kind", ""))
	return ""


## Public availability from /status {online, accepting}: [label, color].
func server_state() -> Array:
	if server.is_empty():
		return ["Mất kết nối", T.color("danger")]
	if not server.get("online", false):
		return ["Bảo trì", T.color("danger")]
	if not server.get("accepting", false):
		return ["Tạm hết chỗ", T.color("warn")]
	return ["Sẵn sàng", T.color("success")]


## Plan with the lowest price — the entry price ("Từ …") and the low-balance threshold.
func cheapest_plan() -> Dictionary:
	var best: Dictionary = {}
	for p in config.get("plans", []):
		if best.is_empty() or int(p.price) < int(best.price):
			best = p
	return best


## Plan with the lowest price per day — the "Tiết kiệm nhất" badge.
func best_value_plan() -> Dictionary:
	var best: Dictionary = {}
	for p in config.get("plans", []):
		if best.is_empty() or float(p.price) / maxf(1.0, float(p.days)) < float(best.price) / maxf(1.0, float(best.days)):
			best = p
	return best


func logout_all() -> void:
	var r: Dictionary = await api.request("/auth/logout-all", Api.POST)
	if not r.ok:
		toast(r.error, true)
		return
	api.token = ""
	logout()
	toast("Đã đăng xuất khỏi mọi thiết bị.")


func logout() -> void:
	if not api.token.is_empty():
		api.request("/auth/logout", Api.POST)
	api.token = ""
	user = {}
	thumbs.clear()
	set_immersive(false)
	tabs = []
	slots = []
	jars = []
	wallet = {}
	admin = {}
	save_settings()
	close_modal()
	go("login")


func _on_unauthorized() -> void:
	if page_id == "login":
		return
	logout()
	toast("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.", true)


# ---------------- navigation ----------------

func go(id: String, params: Dictionary = {}) -> void:
	if id != "login" and api.token.is_empty():
		id = "login"
	if id == "admin" and not is_admin():
		id = "tabs"
	close_modal()
	if page:
		_retire(page)
		page = null
	if immersive:
		set_immersive(false)
	page_id = id
	page_params = params
	_render_announcement()
	var script: GDScript = PAGES.get(id, PAGES["tabs"])
	page = script.new()
	page.set("app", self)
	page.set("params", params)
	if id == "login":
		_shell.visible = false
		_login_layer.visible = true
		_login_layer.add_child(page)
	else:
		_shell.visible = true
		_login_layer.visible = false
		_page_margin.add_child(page)
		_scroll.scroll_vertical = 0
		_scroll.set_deferred("scroll_vertical", 0)
		_render_header()
		_rebuild_nav()
	page.build()
	# Page transition: quick fade-in (never blocks input); skipped when reduce_motion is on.
	if motion:
		page.modulate.a = 0.0
		create_tween().tween_property(page, "modulate:a", 1.0, FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if id != "login":
		refresh()


## Pages may still be awaiting HTTP when the user navigates; keep them alive (out of tree) until
## their requests have certainly finished, so coroutines never resume on a freed instance.
func _retire(node: Node) -> void:
	if node.get_parent():
		node.get_parent().remove_child(node)
	_retired.append({"node": node, "at": Time.get_ticks_msec()})


func _exit_tree() -> void:
	for item in _retired:
		if is_instance_valid(item.node):
			item.node.free()
	_retired.clear()


func _sweep_retired() -> void:
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for item in _retired:
		if now - int(item.at) > 150000:
			if is_instance_valid(item.node):
				item.node.free()
		else:
			keep.append(item)
	_retired = keep


## tokens.user_menu entries this app has a page for (downloads are web-only).
func user_menu_items() -> Array:
	var items: Array = T.user_menu().filter(func(it: Dictionary) -> bool: return PAGES.has(str(it.id)))
	var ids := items.map(func(it: Dictionary) -> String: return str(it.id))
	for extra in EXTRA_MENU:
		if not str(extra.id) in ids:
			items.append(extra)
	return items


## Maintenance mode (config.maintenance): users can't rent, buy slots or upload JARs.
func maintenance_on() -> bool:
	return bool(config.get("maintenance", {}).get("enabled", false)) and not is_admin()


## Follows a notification/web route: "/wallet", "/tabs/ID" (viewer), "/support/ID", "/referral"…
func open_link(link: String) -> void:
	var parts := link.trim_prefix("/#").trim_prefix("/").split("/", false)
	if parts.is_empty():
		return
	match parts[0]:
		"tabs":
			if parts.size() > 1:
				go("viewer", {"id": parts[1]})
			else:
				go("tabs")
		"support":
			go("support", {"id": parts[1]} if parts.size() > 1 else {})
		_:
			if PAGES.has(parts[0]) and parts[0] != "login":
				go(parts[0])


func nav_items() -> Array:
	var items: Array = []
	for item in T.nav():
		if item.get("admin", false) and not is_admin():
			continue
		items.append(item)
	return items


func page_title() -> String:
	match page_id:
		"viewer": return "Màn hình tab"
	for item in T.nav() + T.user_menu():
		if item.id == page_id:
			return str(item.label)
	return T.brand("name")


# ---------------- shell layout ----------------

func _build_shell() -> void:
	_login_layer = Control.new()
	_login_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_login_layer.visible = false
	add_child(_login_layer)

	_shell = HBoxContainer.new()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.add_theme_constant_override("separation", 0)
	_shell.visible = false
	add_child(_shell)

	# Sidebar
	_sidebar = PanelContainer.new()
	_sidebar.theme_type_variation = "Sidebar"
	_sidebar.custom_minimum_size.x = 232
	_shell.add_child(_sidebar)
	var side := UI.vbox(_sidebar, T.space("xs"))
	_brand_box = UI.hbox(side, T.space("sm"))
	_render_brand()
	var gap := Control.new()
	gap.custom_minimum_size.y = T.space("lg")
	side.add_child(gap)
	_side_nav = UI.vbox(side, T.space("xs"))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(fill)
	_side_footer = UI.vbox(side, T.space("sm"))

	# Main column
	var main_col := VBoxContainer.new()
	main_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_col.add_theme_constant_override("separation", 0)
	_shell.add_child(main_col)

	_header = PanelContainer.new()
	_header.theme_type_variation = "Header"
	main_col.add_child(_header)
	var hrow := UI.hbox(_header, T.space("md"))
	_header_brand = UI.image(hrow, APP_ICON, Vector2(30, 30))
	_header_title = UI.label(hrow, "", "HeadingLabel", false)
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.clip_text = true
	_header_right = UI.hbox(hrow, T.space("sm"))
	_header_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_right.alignment = BoxContainer.ALIGNMENT_END

	# Banners (components.banner): full-width strip, icon left, centred text, action/close right.
	var maint := _banner(main_col, "warn", "alert")
	_maint = maint[0]
	_maint_label = maint[1]
	var ann := _banner(main_col, "accent", "bell")
	_announce = ann[0]
	_announce_label = ann[1]
	UI.icon_button(ann[2], "x", func() -> void:
		set_pref("dismissed_announcement", _announce_label.text)
		_announce.visible = false, "Ẩn thông báo", "sm").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var off := _banner(main_col, "danger", "alert")
	_offline = off[0]
	(off[1] as Label).text = Api.NETWORK_ERROR
	UI.button(off[2], "Thử lại", retry, "GhostButton", "sm").size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_scroll = ScrollContainer.new()
	_scroll.scroll_deadzone = 12  # touch drag-to-scroll without stealing taps
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_col.add_child(_scroll)
	_page_margin = MarginContainer.new()
	_page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page_margin)

	_bottom_nav = PanelContainer.new()
	_bottom_nav.theme_type_variation = "BottomNav"
	_bottom_nav.visible = false
	main_col.add_child(_bottom_nav)
	_bottom_row = UI.hbox(_bottom_nav, 0)
	_apply_layout()


func _build_layers() -> void:
	# Full-window layer pages can draw into (viewer gamepad mode); above the shell, below dialogs.
	page_overlay = Control.new()
	page_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_overlay)
	# Dialog layer: dim backdrop + one panel positioned by _layout_modal (centred on desktop,
	# bottom sheet on narrow windows) — sizes from tokens.components.dialog.
	_overlay = PanelContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(host)
	_modal_dim = ColorRect.new()
	_modal_dim.color = Color(0, 0, 0, 0.6)
	_modal_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_modal())
	host.add_child(_modal_dim)
	# Phones: the on-screen keyboard covers the bottom of the window (Godot does not resize for it), so an
	# open dialog with a text field is moved up above the keyboard while it is shown.
	if OS.has_feature("mobile"):
		var kb := Timer.new()
		kb.wait_time = 0.15
		kb.autostart = true
		add_child(kb)
		kb.timeout.connect(_watch_keyboard)
	_modal_panel = PanelContainer.new()
	_modal_panel.theme_type_variation = "Modal"
	host.add_child(_modal_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_modal_panel.add_child(col)
	_sheet_handle = CenterContainer.new()
	_sheet_handle.custom_minimum_size.y = 16
	col.add_child(_sheet_handle)
	var bar := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(T.color("muted"), 0.5)
	hsb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", hsb)
	bar.custom_minimum_size = Vector2(36, 4)
	_sheet_handle.add_child(bar)
	_modal_head = HBoxContainer.new()
	_modal_head.add_theme_constant_override("separation", T.space("md"))
	_modal_head.custom_minimum_size.y = T.compf("dialog.header_height", 56)
	_modal_head.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_child(_modal_head)
	_modal_title = UI.label_clip(_modal_head, "", "HeadingLabel")
	_modal_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close_btn := UI.icon_button(_modal_head, "x", close_modal, "Đóng", "sm")
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.scroll_deadzone = 12
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_modal_scroll)
	var gap := Control.new()
	gap.custom_minimum_size.y = T.compf("dialog.footer_gap", 12)
	gap.name = "FooterGap"
	col.add_child(gap)
	_modal_footer = UI.hbox(col, T.space("sm"))
	_modal_footer.alignment = BoxContainer.ALIGNMENT_END
	_modal_footer.visible = false

	# Toast stack (components.toast): top-right on desktop, top-centre full width on phones.
	_toast_layer = Control.new()
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)
	_build_busy_bar()


## Thin running bar along the top edge while a user action waits for the server (shown after 250 ms so quick
## actions don't flash), so a slow reply never looks like the app ignored the tap.
func _build_busy_bar() -> void:
	_busy_bar = Control.new()
	_busy_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_busy_bar.custom_minimum_size.y = 3
	_busy_bar.size.y = 3
	_busy_bar.clip_contents = true
	_busy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy_bar.visible = false
	add_child(_busy_bar)
	var seg := ColorRect.new()
	seg.color = T.color("accent")
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy_bar.add_child(seg)
	_busy_bar.set_meta("seg", seg)
	api.busy_changed.connect(func(busy: bool) -> void:
		if not busy:
			_busy_bar.visible = false
			if _busy_tween:
				_busy_tween.kill()
			return
		await get_tree().create_timer(0.25).timeout
		if not api.is_busy() or _busy_bar.visible:
			return
		_busy_bar.visible = true
		var w := maxf(size.x, 1.0)
		seg.size = Vector2(w * 0.3, 3)
		_busy_tween = create_tween().set_loops()
		_busy_tween.tween_property(seg, "position:x", w, 0.9).from(-w * 0.3).set_trans(Tween.TRANS_SINE))


func _on_connectivity(is_online: bool) -> void:
	if _offline:
		_offline.visible = not is_online and page_id != "login"
	if is_online and page_id != "login":
		load_status()


func retry() -> void:
	await load_public()
	if not api.token.is_empty():
		if user.is_empty():
			var me: Dictionary = await api.request("/me")
			if me.ok:
				user = me.data
				await enter_app()
				return
		await refresh(true)


## Phone viewer: hide app chrome (header + bottom bar) so the game screen gets the whole display.
func set_immersive(on: bool) -> void:
	immersive = on
	_apply_layout()


func _start_timers() -> void:
	var data_timer := Timer.new()
	data_timer.wait_time = T.poll("data")
	data_timer.timeout.connect(func() -> void:
		if page_id != "login" and not api.token.is_empty():
			refresh())
	add_child(data_timer)
	data_timer.start()
	var status_timer := Timer.new()
	status_timer.wait_time = T.poll("status")
	status_timer.timeout.connect(load_status)
	add_child(status_timer)
	status_timer.start()
	var sweep := Timer.new()
	sweep.wait_time = 30.0
	sweep.timeout.connect(_sweep_retired)
	add_child(sweep)
	sweep.start()


func _on_resized() -> void:
	var was := compact
	compact = size.x < COMPACT_WIDTH or size.y < COMPACT_HEIGHT
	_apply_layout()
	_layout_modal()
	_place_toast()
	if was != compact:
		# Switch between desktop and phone styling (text size, touch targets) and rebuild the page.
		apply_prefs()
	elif page and page.has_method("on_resize") and absf(size.x - _last_width) > 1.0:
		page.on_resize()
	_last_width = size.x


func _apply_layout() -> void:
	if not _sidebar:
		return
	_sidebar.visible = not compact
	_bottom_nav.visible = compact and not immersive
	_header.visible = not (compact and immersive)
	_header_brand.visible = compact
	_header_title.visible = not compact
	_apply_safe_area()
	var pad := T.space("lg") if compact else T.space("xl")
	var extra := maxf(0.0, (_main_width() - pad * 2 - MAX_CONTENT) / 2.0)
	for side in ["left", "right"]:
		_page_margin.add_theme_constant_override("margin_" + side, int(pad + extra))
	_page_margin.add_theme_constant_override("margin_top", pad)
	_page_margin.add_theme_constant_override("margin_bottom", T.space("xxl"))
	_header_title.theme_type_variation = "SubheadingLabel" if compact else "HeadingLabel"
	var hs: StyleBoxFlat = (theme.get_stylebox("panel", "Header") as StyleBoxFlat)
	hs.content_margin_left = pad
	hs.content_margin_right = pad


func _main_width() -> float:
	return size.x - _insets.position.x - _insets.size.x - (0.0 if compact else _sidebar.custom_minimum_size.x)


## Width available to page content (for grids).
func content_width() -> float:
	var pad := T.space("lg") if compact else T.space("xl")
	return minf(_main_width() - pad * 2, MAX_CONTENT) - 12


## Phones: keep the shell (bottom bar, viewer) inside the display safe area (notches, gesture bar).
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var k := maxf(get_window().content_scale_factor, 0.01)
	_insets = Rect2(safe.position.x / k, safe.position.y / k, maxf(0.0, win.x - safe.end.x) / k, maxf(0.0, win.y - safe.end.y) / k)
	for layer in [_shell, _login_layer]:
		layer.offset_left = _insets.position.x
		layer.offset_top = _insets.position.y
		layer.offset_right = -_insets.size.x
		layer.offset_bottom = -_insets.size.y


const BOTTOM_MAX := 5  # phone bottom bar: first 4 items + "Thêm" when there are more


func _rebuild_nav() -> void:
	UI.clear(_side_nav)
	UI.clear(_bottom_row)
	var current := "tabs" if page_id == "viewer" else page_id
	var items := nav_items()
	for item in items:
		_side_entry(item, item.id == current)
	var bottom := items if items.size() <= BOTTOM_MAX else items.slice(0, BOTTOM_MAX - 1)
	for item in bottom:
		_bottom_entry(str(item.icon), str(item.label), item.id == current, go.bind(str(item.id)))
	if items.size() > BOTTOM_MAX:
		var rest := items.slice(BOTTOM_MAX - 1)
		var in_rest := rest.any(func(it: Dictionary) -> bool: return it.id == current) or current in T.user_menu().map(func(it: Dictionary) -> String: return str(it.id))
		_bottom_entry("more", "Thêm", in_rest, _more_sheet.bind(rest))


func _side_entry(item: Dictionary, active: bool) -> void:
	var id: String = item.id
	var b := UI.button(_side_nav, "", func() -> void: go(id), "NavButtonActive" if active else "NavButton")
	b.custom_minimum_size.y = UI.target_h(40)
	var row := UI.hbox(b, T.space("md"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = T.space("md")
	var ink := T.accent_text() if active else T.color("muted")
	UI.nav_icon(row, str(item.get("icon", "")), ink, 18)
	var l := UI.label(row, str(item.label), "StrongLabel" if active else "", false)
	l.add_theme_color_override("font_color", ink)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if id == "admin":
		var n := int(admin.get("stats", {}).get("pending_jars", 0))
		if n > 0:
			UI.spacer(row)
			UI.badge(row, str(n), T.color("warn"))


func _bottom_entry(icon: String, text: String, active: bool, cb: Callable) -> void:
	var bb := UI.button(_bottom_row, "", cb, "BottomNavButtonActive" if active else "BottomNavButton")
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.custom_minimum_size = Vector2(0, 56)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	bb.add_child(col)
	var ic := UI.nav_icon(null, icon, T.accent_text() if active else T.color("dim"), 20)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var bl := UI.label(col, text, "", false)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.add_theme_font_size_override("font_size", 11)
	bl.add_theme_color_override("font_color", T.accent_text() if active else T.color("muted"))
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.clip_text = true


## Phone "Thêm" sheet: overflow nav items + user menu + sign out.
func _more_sheet(rest: Array) -> void:
	var body := open_modal("Thêm", 420)
	for item in rest + user_menu_items():
		var id := str(item.id)
		var b := UI.button(body, "", func() -> void: go(id), "NavButtonActive" if id == page_id else "NavButton")
		b.custom_minimum_size.y = 48
		var row := UI.hbox(b, T.space("md"))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = T.space("md")
		UI.nav_icon(row, str(item.get("icon", "")), T.color("muted"), 20)
		UI.label(row, str(item.label), "StrongLabel", false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Same as the web "Thêm" sheet: the phone header has no room for the theme switch.
	var dark := T.mode == "dark"
	var tb := UI.button(body, "", func() -> void:
		close_modal()
		toggle_theme(), "NavButton")
	tb.custom_minimum_size.y = 48
	var trow := UI.hbox(tb, T.space("md"))
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trow.offset_left = T.space("md")
	UI.nav_icon(trow, "sun" if dark else "moon", T.color("muted"), 20)
	UI.label(trow, "Giao diện sáng" if dark else "Giao diện tối", "StrongLabel", false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.button(body, "Đăng xuất", logout, "DangerButton")


## Light <-> dark, from what is shown now (a "system" choice becomes an explicit one, like the web toggle).
func toggle_theme() -> void:
	set_user_pref("theme", "light" if T.mode == "dark" else "dark")


func _render_header() -> void:
	if not _header_title:
		return
	_header_title.text = page_title()
	UI.clear(_header_right)
	if user.is_empty():
		return
	if not compact:  # phones: in the "Thêm" sheet
		var dark := T.mode == "dark"
		UI.icon_button(_header_right, "sun" if dark else "moon", toggle_theme, "Giao diện sáng" if dark else "Giao diện tối", "md")
	var bell := UI.icon_button(_header_right, "bell", open_notifications, "Thông báo", "md")
	_bell = bell
	var unread := int(notifications.get("unread", 0))
	if unread > 0:
		var dot := PanelContainer.new()
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = T.color("danger")
		dsb.set_corner_radius_all(9)
		dsb.content_margin_left = 5
		dsb.content_margin_right = 5
		dot.add_theme_stylebox_override("panel", dsb)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dl := Label.new()
		dl.text = str(unread) if unread < 100 else "99+"
		dl.add_theme_font_size_override("font_size", int(T.compf("badge.font", 12)) - 1)
		dl.add_theme_color_override("font_color", Color.WHITE)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_child(dl)
		var cm := T.compf("badge.counter_min_width", 18)
		dot.custom_minimum_size = Vector2(cm, cm)
		dot.position = Vector2(bell.custom_minimum_size.x - cm + 2, 2)
		bell.add_child(dot)
	var bal := UI.button(_header_right, UI.money(user.get("balance", 0)), func() -> void: go("wallet"), "ChipButtonActive")
	bal.tooltip_text = "Số dư ví"
	bal.add_theme_font_override("font", AppTheme.font_display_bold)
	bal.add_theme_font_size_override("font_size", T.font_size("lg"))
	bal.custom_minimum_size.y = UI.btn_h("md")
	# Account menu: user_menu items + sign out (secondary actions live in a popup, not the header).
	var menu_items: Array = []
	for item in user_menu_items():
		menu_items.append([str(item.label), go.bind(str(item.id))])
	menu_items.append(["Đăng xuất", logout])
	var acc := UI.menu_button(_header_right, ("Tài khoản" if compact else str(user.get("name", "Tài khoản"))) + "  ▾", menu_items, "GhostButton")
	acc.custom_minimum_size.y = UI.target_h(34)
	for c in _header_right.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_right.alignment = BoxContainer.ALIGNMENT_END


## Returns [panel, label, row] for a banner strip in the given status colour.
func _banner(parent: Node, color_key: String, icon: String) -> Array:
	var p := PanelContainer.new()
	p.visible = false
	p.set_meta("color_key", color_key)
	var c := T.color(color_key)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c, 0.14)
	sb.border_color = Color(c, 0.45)
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(int(T.compf("banner.radius", 0)))
	sb.content_margin_left = T.space("lg")
	sb.content_margin_right = T.space("sm")
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = T.compf("banner.height", 44)
	parent.add_child(p)
	var row := UI.hbox(p, int(T.compf("button.gap", 8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UI.nav_icon(row, icon, c, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UI.label(row, "", "")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", int(T.compf("banner.font", 14)))
	l.add_theme_color_override("font_color", c.lightened(0.25) if T.mode == "dark" else c.darkened(0.3))
	p.set_meta("label", l)
	p.set_meta("icon", ic)
	return [p, l, row]


## Re-applies banner colours after a theme/accent change (banners are built once).
func _restyle_banners() -> void:
	for p in [_maint, _announce, _offline]:
		if not is_instance_valid(p):
			continue
		var c := T.color(str(p.get_meta("color_key", "accent")))
		var sb: StyleBoxFlat = (p.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.bg_color = Color(c, 0.14)
		sb.border_color = Color(c, 0.45)
		p.add_theme_stylebox_override("panel", sb)
		(p.get_meta("label") as Label).add_theme_color_override("font_color", c.lightened(0.25) if T.mode == "dark" else c.darkened(0.3))
		p.get_meta("icon").set("color", c)


func _render_brand() -> void:
	UI.clear(_brand_box)
	UI.image(_brand_box, APP_ICON, Vector2(36, 36))
	UI.wordmark(_brand_box, T.font_size("xl")).size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Admin-editable site announcement (config.site.announcement): dismissible bar above the page.
func _render_announcement() -> void:
	if not _announce:
		return
	var text := str(config.get("site", {}).get("announcement", "")).strip_edges()
	_announce.visible = not text.is_empty() and text != str(pref("dismissed_announcement", "")) and page_id != "login"
	_announce_label.text = text
	_announce_label.tooltip_text = text
	if _maint:
		var m: Dictionary = config.get("maintenance", {})
		_maint.visible = bool(m.get("enabled", false)) and page_id != "login"
		var msg := str(m.get("message", "")).strip_edges()
		if msg.is_empty():
			msg = "Hệ thống đang bảo trì."
		if int(m.get("until", 0)) > 0:
			msg += " Dự kiến xong lúc %s." % UI.datetime(m.until)
		if not is_admin():
			msg += " Tạm thời chưa thể thuê tab, mua slot hoặc tải file."
		_maint_label.text = "Bảo trì: " + msg


func _render_sidebar_footer() -> void:
	if not _side_footer:
		return
	UI.clear(_side_footer)
	var row := UI.hbox(_side_footer, T.space("sm"))
	UI.label(row, "Dịch vụ", "MutedLabel", false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := server_state()
	UI.badge(row, st[0], st[1])


# ---------------- modal ----------------

## Dialog width from tokens.components.dialog.width: legacy pixel hints map to sm/md/lg/xl.
static func dialog_width(want: float) -> float:
	var key := "sm" if want <= 440.0 else ("md" if want <= 600.0 else ("lg" if want <= 800.0 else "xl"))
	return T.compf("dialog.width." + key, 560)


func sheet_mode() -> bool:
	return size.x <= 640.0


## Opens a dialog and returns its body VBox. An empty title hides the header (used by confirm()).
func open_modal(title: String, width: float = 560.0) -> VBoxContainer:
	if _modal_body:
		_retire(_modal_body)
	UI.clear(_modal_footer)
	_modal_footer.visible = false
	_modal_footer.set_meta("equal", false)
	_modal_body = UI.vbox(null, T.space("lg"))
	_modal_scroll.add_child(_modal_body)
	_modal_width = dialog_width(width)
	_modal_title.text = title
	_modal_title.tooltip_text = title
	_modal_head.visible = not title.is_empty()
	_modal_body.minimum_size_changed.connect(_layout_modal)
	_overlay.visible = true
	_close_popover()
	_layout_modal()
	if _modal_tween:
		_modal_tween.kill()
	if not motion:
		return _modal_body
	_modal_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_modal_dim.modulate.a = 0.0
	_modal_tween.tween_property(_modal_dim, "modulate:a", 1.0, 0.16)
	if sheet_mode():
		# Animate an offset rather than the position: the body is filled after this returns, so the
		# final height isn't known yet; _layout_modal applies the offset on every relayout.
		_sheet_offset = size.y * 0.4
		_modal_tween.tween_method(func(v: float) -> void:
			_sheet_offset = v
			_layout_modal(), size.y * 0.4, 0.0, 0.22)
	else:
		_modal_panel.modulate.a = 0.0
		_modal_panel.scale = Vector2(0.97, 0.97)
		_modal_tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.16)
		_modal_tween.tween_property(_modal_panel, "scale", Vector2.ONE, 0.18)
	return _modal_body


func close_modal() -> void:
	if _modal_body:
		_retire(_modal_body)
		_modal_body = null
	if _overlay and _overlay.visible:
		if _modal_tween:
			_modal_tween.kill()
		_overlay.visible = false
		_modal_dim.modulate.a = 1.0
		_sheet_offset = 0.0
		_modal_panel.modulate.a = 1.0
		_modal_panel.scale = Vector2.ONE


## Sticky action row for the open dialog (stays visible while the body scrolls). Buttons are
## right-aligned on desktop; in bottom-sheet mode they take the full width.
func modal_footer() -> HBoxContainer:
	_modal_footer.visible = true
	if not _modal_footer.minimum_size_changed.is_connected(_layout_modal):
		_modal_footer.minimum_size_changed.connect(_layout_modal)
	if not _modal_footer.child_entered_tree.is_connected(_on_footer_child):
		_modal_footer.child_entered_tree.connect(_on_footer_child)
	return _modal_footer


func _on_footer_child(_n: Node) -> void:
	_layout_modal.call_deferred()


func modal_open() -> bool:
	return _overlay and _overlay.visible


func _layout_modal() -> void:
	if not _modal_body or not is_instance_valid(_modal_body):
		return
	var sheet := sheet_mode()
	var pad := T.space("lg") if sheet else int(T.compf("dialog.padding", 24))
	var w := size.x if sheet else minf(_modal_width, size.x - 48.0)
	# Panel style: centred card, or bottom sheet with 20 px top corners and safe-area bottom padding.
	var sb: StyleBoxFlat = (theme.get_stylebox("panel", "Modal") as StyleBoxFlat).duplicate()
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = 0 if sheet else pad - 8
	sb.content_margin_bottom = pad + (_insets.size.y if sheet else 0.0)
	if sheet:
		sb.corner_radius_top_left = 20
		sb.corner_radius_top_right = 20
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_bottom = 0
		sb.border_width_left = 0
		sb.border_width_right = 0
	_modal_panel.add_theme_stylebox_override("panel", sb)
	_sheet_handle.visible = sheet
	# Footer: equal halves (confirm), full-width primary (sheet), or right-aligned (desktop).
	var equal: bool = _modal_footer.get_meta("equal", false)
	for c in _modal_footer.get_children():
		if c is Control:
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if (sheet or equal) else Control.SIZE_SHRINK_END
			(c as Control).size_flags_stretch_ratio = 1.0
	var max_h := size.y - _kb_h - (_insets.position.y + 24.0 if sheet else 48.0)
	if _kb_top:
		max_h = size.y * 0.45 - _insets.position.y
	var head_h := _modal_head.get_combined_minimum_size().y if _modal_head.visible else 0.0
	var handle_h := _sheet_handle.get_combined_minimum_size().y if sheet else 0.0
	var foot_h := (_modal_footer.get_combined_minimum_size().y + T.compf("dialog.footer_gap", 12)) if _modal_footer.visible else 0.0
	var chrome := sb.content_margin_top + sb.content_margin_bottom + head_h + handle_h + foot_h
	var inner_w := w - pad * 2
	_modal_body.custom_minimum_size.x = inner_w - 8
	var body_h := minf(_modal_body.get_combined_minimum_size().y, max_h - chrome)
	_modal_scroll.custom_minimum_size = Vector2(inner_w, maxf(body_h, 0.0))
	(_modal_panel.get_child(0).get_node("FooterGap") as Control).visible = _modal_footer.visible
	_modal_panel.reset_size()
	var ph := _modal_panel.get_combined_minimum_size().y
	_modal_panel.size = Vector2(w, ph)
	# The keyboard covers the safe-area inset too: a sheet resting on it needs no bottom inset padding.
	if sheet and (_kb_h > 0.0 or _kb_top):
		sb.content_margin_bottom = pad
		if _kb_top:
			sb.corner_radius_bottom_left = 20
			sb.corner_radius_bottom_right = 20
		_modal_panel.reset_size()
		ph = _modal_panel.get_combined_minimum_size().y
		_modal_panel.size = Vector2(w, ph)
	var room := size.y - _kb_h  # visible height above the keyboard
	_modal_panel.position = Vector2(0, room - ph + _sheet_offset) if sheet else Vector2(floorf((size.x - w) / 2.0), floorf(maxf(8.0, (room - ph) / 2.0)))
	if _kb_top:
		_modal_panel.position.y = _insets.position.y + 8.0
	_modal_panel.pivot_offset = _modal_panel.size / 2.0


func _watch_keyboard() -> void:
	var px := DisplayServer.virtual_keyboard_get_height()
	var known := px > 0
	if not known and OS.get_name() == "Android":
		var ime := _android_ime_px()
		if ime >= 0:
			px = ime
			known = true
	var win := DisplayServer.window_get_size()
	var h := px * size.y / float(win.y) if win.y > 0 and px > 0 else 0.0
	var focus := get_viewport().gui_get_focus_owner()
	var typing := _overlay != null and _overlay.visible and (focus is LineEdit or focus is TextEdit) and _modal_panel.is_ancestor_of(focus)
	var top := typing and not known
	if absf(h - _kb_h) < 1.0 and top == _kb_top:
		return
	_kb_h = h
	_kb_top = top
	if _overlay and _overlay.visible:
		_layout_modal()


## Keyboard height in px from Android's window insets, or -1 when they cannot be read. Godot reports 0 on
## edge-to-edge windows, where the keyboard does not shrink the visible frame; the insets still have it.
func _android_ime_px() -> int:
	if _ime_view == null:
		_ime_view = false
		if Engine.has_singleton("AndroidRuntime"):
			var activity: Variant = Engine.get_singleton("AndroidRuntime").getActivity()
			if activity != null:
				var view: Variant = activity.getWindow().getDecorView()
				if view != null:
					_ime_view = view
	if _ime_view is bool:
		return -1
	var ins: Variant = _ime_view.getRootWindowInsets()
	if ins == null:
		return -1
	# System-window insets include the keyboard; stable insets are the bars alone.
	return maxi(0, int(ins.getSystemWindowInsetBottom()) - int(ins.getStableInsetBottom()))


## Confirm (components.confirm): round icon on top, centred title + text, two equal buttons.
func confirm(title: String, text: String, ok_text: String, on_ok: Callable, danger: bool = false) -> void:
	var body := open_modal("", T.compf("confirm.width", 400))
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := Control.new()
	top.custom_minimum_size.y = T.space("sm")
	body.add_child(top)
	var c := T.color("danger") if danger else T.color("warn")
	var circle := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(c, 0.16)
	csb.set_corner_radius_all(int(T.compf("confirm.icon", 40)))
	circle.add_theme_stylebox_override("panel", csb)
	var side := T.compf("confirm.icon", 40)
	circle.custom_minimum_size = Vector2(side, side)
	circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(circle)
	var cc := CenterContainer.new()
	circle.add_child(cc)
	UI.nav_icon(cc, "alert", c, side * 0.5)
	var t := UI.label(body, title, "SubheadingLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := UI.label(body, text, "BodyMutedLabel")
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := modal_footer()
	row.set_meta("equal", true)
	UI.button(row, "Hủy", close_modal, "")
	UI.button(row, ok_text, func() -> void:
		close_modal()
		on_ok.call(), "DangerButton" if danger else "PrimaryButton")
	_layout_modal()


# ---------------- toasts ----------------

## Toast (components.toast): status bar + icon, 1–2 lines, close button; at most max_visible stacked.
## kind: success | info | warn | danger (error=true → danger).
func toast(text: String, error: bool = false, kind: String = "") -> void:
	if kind.is_empty():
		kind = "danger" if error else "success"
	var color := T.color(kind)
	var p := PanelContainer.new()
	p.theme_type_variation = "Toast"
	var sb: StyleBoxFlat = (theme.get_stylebox("panel", "Toast") as StyleBoxFlat).duplicate()
	sb.border_color = color
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = T.compf("toast.min_height", 48)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast_layer.add_child(p)
	var row := UI.hbox(p, int(T.compf("button.gap", 8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon_name: String = {"success": "check-circle", "info": "info", "warn": "alert", "danger": "alert"}.get(kind, "info")
	UI.nav_icon(row, icon_name, color, T.compf("toast.icon", 20))
	var l := UI.label(row, text, "")
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.tooltip_text = text
	var x := UI.icon_button(row, "x", func() -> void: _dismiss_toast(p), "Đóng", "sm")
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toasts.append(p)
	var max_n := int(T.compf("toast.max_visible", 3))
	while _toasts.size() > max_n:
		_dismiss_toast(_toasts[0], true)
	_restack(p)
	var hold := get_tree().create_timer(T.compf("toast.duration_ms", 3500) / 1000.0 + (1.0 if kind == "danger" else 0.0))
	hold.timeout.connect(func() -> void: _dismiss_toast(p))


func _toast_rect_x(w: float) -> float:
	return 12.0 if sheet_mode() else size.x - w - 16.0


func _toast_width() -> float:
	return size.x - 24.0 if sheet_mode() else T.compf("toast.width", 360)


func _toast_top() -> float:
	if sheet_mode() or page_id == "login" or not _header or not _header.visible:
		return _insets.position.y + 12.0
	return _header.get_global_rect().end.y + 16.0


## Positions the stack (newest on top); slides the new toast in.
func _restack(new_toast: Control = null) -> void:
	var w := _toast_width()
	var y := _toast_top()
	var gap := T.compf("toast.gap", 8)
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Control = _toasts[i]
		if not is_instance_valid(t):
			continue
		t.size = Vector2(w, 0)
		t.reset_size()
		t.size.x = w
		var target := Vector2(_toast_rect_x(w), y)
		if t == new_toast and motion:
			t.position = target + (Vector2(0, -16) if sheet_mode() else Vector2(32, 0))
			t.modulate.a = 0.0
			var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "position", target, 0.18)
			tw.tween_property(t, "modulate:a", 1.0, 0.18)
		elif motion:
			create_tween().tween_property(t, "position", target, 0.15)
		else:
			t.position = target
		y += t.size.y + gap


func _dismiss_toast(t: Control, instant: bool = false) -> void:
	if not is_instance_valid(t) or not t in _toasts:
		return
	_toasts.erase(t)
	if instant or not motion:
		t.queue_free()
	else:
		var tw := create_tween()
		tw.tween_property(t, "modulate:a", 0.0, 0.15)
		tw.tween_callback(t.queue_free)
	_restack()


func _place_toast() -> void:
	_restack()


# ---------------- keyboard ----------------

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and modal_open():
		close_modal()
		get_viewport().set_input_as_handled()
		return
	if page and page.has_method("on_key") and not modal_open():
		page.on_key(event)



# ---------------- notifications ----------------

func open_notifications() -> void:
	if sheet_mode() or not is_instance_valid(_bell):
		var body := open_modal("Thông báo", 960)
		_modal_scroll.custom_minimum_size.y = 0
		_fill_notifications(body, true)
		var row := modal_footer()
		var all := UI.button(row, "Đánh dấu đã đọc tất cả", _mark_all_read, "")
		all.disabled = int(notifications.get("unread", 0)) == 0
		# Mobile: the sheet uses the full screen height.
		_modal_body.custom_minimum_size.y = size.y
		_layout_modal()
		return
	_close_popover()
	_pop_layer = Control.new()
	_pop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_pop_layer.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_popover())
	add_child(_pop_layer)
	move_child(_pop_layer, _overlay.get_index())
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = (theme.get_stylebox("panel", "Modal") as StyleBoxFlat).duplicate()
	sb.set_corner_radius_all(int(T.compf("popover.notifications.radius", 14)))
	sb.content_margin_left = T.space("sm")
	sb.content_margin_right = T.space("sm")
	sb.content_margin_top = T.space("sm")
	sb.content_margin_bottom = T.space("sm")
	panel.add_theme_stylebox_override("panel", sb)
	_pop_layer.add_child(panel)
	var col := UI.vbox(panel, T.space("xs"))
	var head := UI.hbox(col, T.space("sm"))
	head.custom_minimum_size.y = UI.btn_h("sm") + 8
	var ht := UI.label(head, "Thông báo", "SubheadingLabel", false)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ht.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := UI.button(head, "Đánh dấu đã đọc", _mark_all_read, "GhostButton", "sm")
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.disabled = int(notifications.get("unread", 0)) == 0
	UI.separator(col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := UI.vbox(scroll, T.space("xs"))
	_fill_notifications(list, false)
	var w := T.compf("popover.notifications.width", 380)
	var max_h := minf(T.compf("popover.notifications.max_height", 480), size.y - 80.0)
	list.custom_minimum_size.x = w - T.space("sm") * 2 - 8
	var chrome := head.get_combined_minimum_size().y + 16 + T.space("sm") * 2 + 8
	scroll.custom_minimum_size = Vector2(w - T.space("sm") * 2, minf(list.get_combined_minimum_size().y, max_h - chrome))
	panel.reset_size()
	panel.size.x = w
	var br := _bell.get_global_rect()
	panel.position = Vector2(clampf(br.end.x - w, 8.0, size.x - w - 8.0), br.end.y + 8.0)
	if motion:
		panel.modulate.a = 0.0
		panel.position.y -= 6
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.14)
		tw.tween_property(panel, "position:y", panel.position.y + 6, 0.14)


func _close_popover() -> void:
	if is_instance_valid(_pop_layer):
		_pop_layer.queue_free()
	_pop_layer = null


func _mark_all_read() -> void:
	var r: Dictionary = await api.request("/notifications/read", Api.POST, {"all": true})
	if r.ok:
		notifications["unread"] = 0
		for it in notifications.get("items", []):
			it["read"] = 1
		_close_popover()
		close_modal()
		_render_header()


## Notification rows (components.popover.notifications): unread dot, bold title, 2-line description,
## relative time on the right; empty state with icon.
func _fill_notifications(parent: Node, sheet: bool) -> void:
	var items: Array = notifications.get("items", [])
	if items.is_empty():
		var c := CenterContainer.new()
		c.custom_minimum_size.y = 200
		parent.add_child(c)
		var e := UI.vbox(c, T.space("sm"))
		UI.nav_icon(e, "bell", Color(T.color("muted"), 0.6), 40).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UI.label(e, "Chưa có thông báo", "BodyMutedLabel", false).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	for n in items:
		var unread := not bool(n.get("read", 0))
		var b := UI.button(parent, "", Callable(), "GhostButton")
		b.custom_minimum_size.y = T.compf("popover.notifications.item_min_height", 64)
		var row := UI.hbox(b, T.space("md"))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = T.space("sm")
		row.offset_right = -T.space("sm")
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var dot := Panel.new()
		var ds := T.compf("badge.dot", 8)
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = T.color("accent") if unread else Color.TRANSPARENT
		dsb.set_corner_radius_all(int(ds))
		dot.add_theme_stylebox_override("panel", dsb)
		dot.custom_minimum_size = Vector2(ds, ds)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var col := UI.vbox(row, 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var t := UI.label_clip(col, str(n.get("title", "")), "StrongLabel")
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var body_text := str(n.get("body", ""))
		if not body_text.is_empty():
			var d := UI.label(col, body_text, "MutedLabel")
			d.max_lines_visible = 2
			d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			d.custom_minimum_size.x = 120
		var when := UI.label(row, UI.ago(n.get("created")), "DimLabel", false)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		when.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The row is laid over the button: grow the button to fit title + 2 description lines.
		var line := AppTheme.font_regular.get_height(T.font_size("sm"))
		var need := AppTheme.font_bold.get_height(T.font_size("md")) + (line * 2 + 2 if not body_text.is_empty() else 0.0) + T.space("lg") * 2
		b.custom_minimum_size.y = maxf(T.compf("popover.notifications.item_min_height", 64), need)
		b.tooltip_text = body_text
		var nid := str(n.id)
		var link := str(n.get("link", ""))
		b.pressed.connect(func() -> void:
			api.request("/notifications/read", Api.POST, {"ids": [nid]})
			n["read"] = 1
			notifications["unread"] = maxi(0, int(notifications.get("unread", 0)) - (1 if unread else 0))
			_close_popover()
			close_modal()
			_render_header()
			if not link.is_empty():
				open_link(link))
	if sheet:
		pass
