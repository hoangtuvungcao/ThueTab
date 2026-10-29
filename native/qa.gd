extends RefCounted
## Debug-only screenshot walkthrough. Runs ONLY when launched with the user arg `--qa-screenshot`:
##   godot --path . -- --qa-screenshot [--qa-out=DIR] [--api=URL]
## Credentials are read at runtime from data/QA_LOGIN.txt (user) and data/LOCAL_LOGIN.txt (admin) —
## never stored in code. Flow: login → rent a tab without a game → upload the QA fixture .jar → pick it
## → live stream viewer → every page at 1280×800, 1024×768, 400×860 and 860×400 → admin pages.
## Writes docs/godot-{login,dashboard,nokia,mobile}.png and extra shots to --qa-out (default user://qa).
## Stops the QA tab at the end. The saved login on this device is never modified.

const Api := preload("res://native/api.gd")
const Actions := preload("res://native/pages/tab_actions.gd")
const UIH := preload("res://native/ui.gd")
const TK := preload("res://native/tokens.gd")
const FIXTURE_JAR := "res://web/qa-fixtures/hello-midlet.jar"

var app: Node
var out_dir: String = ""
var tab_id: String = ""


static func requested() -> bool:
	return "--qa-screenshot" in OS.get_cmdline_user_args()


static func _creds(file: String) -> Dictionary:
	# --qa-creds=/abs/path overrides the user account file (temporary QA accounts).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-creds=") and file != "LOCAL_LOGIN.txt":
			file = a.trim_prefix("--qa-creds=")
	var path := file if file.begins_with("/") else ProjectSettings.globalize_path("res://data/" + file)
	var text := FileAccess.get_file_as_string(path)
	var out := {}
	for line in text.split("\n"):
		if line.begins_with("Email:"):
			out["email"] = line.trim_prefix("Email:").strip_edges()
		elif line.begins_with("Password:"):
			out["password"] = line.trim_prefix("Password:").strip_edges()
	return out


func run(main: Node) -> void:
	app = main
	app.persist = false
	out_dir = OS.get_user_data_dir() + "/qa"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-out="):
			out_dir = a.trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var docs := ProjectSettings.globalize_path("res://docs")
	if "--qa-admin-only" in OS.get_cmdline_user_args():
		await app.load_public()
		await _admin()
		app.get_tree().quit()
		return

	if "--qa-plan-check" in OS.get_cmdline_user_args():
		await app.load_public()
		var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
		if not r.ok:
			_fail(r.error)
			return
		app.api.token = str(r.data.token)
		app.user = r.data.user
		await _resize(Vector2i(1280, 800))
		await app.enter_app()
		print("QA: cheapest=%s best_value=%s balance=%s" % [str(app.cheapest_plan().get("price")), str(app.best_value_plan().get("id")), str(app.user.get("balance"))])
		for p in ["tabs", "wallet", "plans"]:
			app.go(p)
			await _wait(1.5)
			await shot(out_dir + "/c-%s-1280x800.png" % p)
		app.get_tree().quit()
		return
	if "--qa-menus" in OS.get_cmdline_user_args():
		await _menus_round()
		app.get_tree().quit()
		return
	if "--qa-theme-probe" in OS.get_cmdline_user_args():
		await app.load_public()
		app.go("login")
		await _wait(0.5)
		print("QA: before mode=", preload("res://native/tokens.gd").mode)
		app.pref_override = {"theme": "light"}
		app.apply_prefs()
		await _wait(0.5)
		print("QA: after mode=", preload("res://native/tokens.gd").mode, " sig=", app.get("_look_sig"), " bg=", preload("res://native/tokens.gd").color("bg"))
		await shot(out_dir + "/probe-light.png")
		app.get_tree().quit()
		return
	if "--qa-polish" in OS.get_cmdline_user_args():
		await _polish_round()
		app.get_tree().quit()
		return
	if "--qa-width" in OS.get_cmdline_user_args():
		await app.load_public()
		var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
		app.api.token = str(r.data.token)
		app.user = r.data.user
		await _resize(Vector2i(400, 860))
		await app.enter_app()
		for p in ["wallet", "plans"]:
			app.go(p)
			await _wait(1.5)
			_print_wide(app.page, app.size.x)
		app.get_tree().quit()
		return
	if "--qa-growth" in OS.get_cmdline_user_args():
		await _growth_round()
		app.get_tree().quit()
		return
	if "--qa-docs" in OS.get_cmdline_user_args():
		await _docs_only(docs)
		app.get_tree().quit()
		return
	if "--qa-audit" in OS.get_cmdline_user_args():
		await _audit_sizes()
		app.get_tree().quit()
		return
	if "--qa-viewer-only" in OS.get_cmdline_user_args():
		await _viewer_sizes()
		app.get_tree().quit()
		return
	await _resize(Vector2i(1280, 800))
	app.api.token = ""
	await app.load_public()
	app.go("login")
	await _wait(1.2)
	await shot(docs + "/godot-login.png")

	var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not r.ok:
		_fail("Đăng nhập QA thất bại: " + r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await app.enter_app()
	await _wait(1.5)
	if app.tabs.is_empty():
		await shot(out_dir + "/desktop-empty.png")
		Actions.rent(app)
		await _wait(1.5)
		await shot(out_dir + "/desktop-rent.png")
		app.close_modal()
		r = await app.api.request("/tabs", Api.POST, {"name": "Tab QA", "plan": "day"})
		print("QA: rent without game -> ", r.ok, " ", r.error)
		await app.refresh(true)
		await _wait(1.0)
		await shot(out_dir + "/desktop-idle.png")
	tab_id = str(app.tabs[0].id)
	await _ensure_game()
	app.go("tabs")
	var waited := 0.0
	while waited < 60.0 and _state() != "running":
		await _wait(1.0)
		waited += 1.0
	print("QA: tab state %s after %.0fs" % [_state(), waited])
	await _wait(TK.poll("wall") * 3.0)
	await shot(docs + "/godot-dashboard.png")

	app.go("viewer", {"id": tab_id})
	waited = 0.0
	while waited < 30.0 and not app.page.source.is_live():
		await _wait(0.5)
		waited += 0.5
	await _wait(2.0)
	print("QA: stream live=%s readout=%s" % [app.page.source.is_live(), app.page._readout.text])
	# Same path as the "60 FPS" button: saved preference + live switch; the choice must stick.
	app.set_user_pref("default_fps", 60)
	app.page.source.set_fps(60)
	await _wait(8.0)
	print("QA: 60fps pref=%d readout=%s" % [app.page._fps_pref(), app.page._readout.text])
	app.page.source.set_fps(30)
	for k in ["5", "F1", "asterisk"]:
		await app.page.send(k)
		await _wait(0.3)
	r = await app.page.source.send_text("qa")
	print("QA: text -> ", r.ok, " ", r.error)
	r = await app.page.source.send_tap(Vector2i(120, 160))
	print("QA: tap -> ", r.ok, " ", r.error)
	await _wait(1.5)
	await shot(docs + "/godot-nokia.png")

	# Long-text robustness: a 60-character Vietnamese tab name and a long JAR file name.
	var long_name := "Tab cày đêm Ngọc Rồng — nhân vật chính số một của tôi ở đây!!"
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"name": long_name.left(60)})
	print("QA: long name -> ", r.ok, " ", r.error)
	var long_jar := out_dir + "/ban-mod-ninja-school-online-phien-ban-dac-biet-tieng-viet-2026-final.jar"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE_JAR), long_jar)
	var has_long := false
	for j in app.jars:
		if str(j.filename).begins_with("ban-mod-ninja"):
			has_long = true
	if not has_long:
		await Actions.upload(app, long_jar)
	await app.refresh(true)

	for theme_id in ["dark", "light"]:
		await app.set_user_pref("theme", theme_id)
		for sz in [Vector2i(1280, 800), Vector2i(1024, 768), Vector2i(400, 860), Vector2i(860, 400)]:
			await _resize(sz)
			var tag := "%s-%dx%d" % [theme_id, sz.x, sz.y]
			for p in ["tabs", "viewer", "wall", "jars", "wallet", "settings"]:
				if p == "viewer":
					app.go("viewer", {"id": tab_id})
				else:
					app.go(p)
				await _wait(2.5 if p in ["tabs", "wall", "viewer"] else 1.0)
				_report_clipping(tag + "-" + p, p != "viewer")
				var path := out_dir + "/%s-%s.png" % [p, tag]
				if theme_id == "dark" and p == "tabs" and sz.x == 1280:
					path = docs + "/godot-dashboard.png"
				elif theme_id == "dark" and p == "viewer" and sz.x == 1280:
					path = docs + "/godot-nokia.png"
				elif theme_id == "dark" and p == "tabs" and sz.x == 400:
					path = docs + "/godot-mobile.png"
				await shot(path)
			if sz.x == 1280:
				app.go("tabs")
				await _wait(0.6)
				Actions.rent(app)
				await _wait(1.2)
				await shot(out_dir + "/rent-%s.png" % tag)
				app.close_modal()
				for t in app.tabs:
					if str(t.id) == tab_id:
						Actions.pick_screen(app, t)
				await _wait(0.8)
				await shot(out_dir + "/screen-picker-%s.png" % tag)
				app.close_modal()
	await app.set_user_pref("theme", "dark")
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"desired": "stopped"})
	print("QA: stopped QA tab -> ", r.ok, " ", r.error)
	app.logout()
	await _resize(Vector2i(400, 860))
	await _wait(1.0)
	await shot(out_dir + "/login-400x860.png")
	await _admin()
	print("QA: done, extra shots in ", out_dir)
	app.get_tree().quit()


func _state() -> String:
	for t in app.tabs:
		if str(t.id) == tab_id:
			return UIH.display_state(t)
	return ""


## Give the QA tab a game: upload the fixture JAR if the account has none, then select it.
func _ensure_game() -> void:
	var t: Dictionary = app.tabs[0]
	var rj: Dictionary = await app.api.request("/jars")
	var jars: Array = rj.data if rj.ok else []
	var jar_id := ""
	for j in jars:
		if str(j.get("status", "")) == "approved":
			jar_id = str(j.id)
	if jar_id.is_empty():
		var jar: Dictionary = await Actions.upload(app, ProjectSettings.globalize_path(FIXTURE_JAR))
		jar_id = str(jar.get("id", ""))
		await app.refresh(true)
		app.go("jars")
		await _wait(1.2)
		await shot(out_dir + "/desktop-jars-after-upload.png")
	var r: Dictionary
	if t.get("custom_jar_id") == null:
		r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"game": "custom-jar", "custom_jar_id": jar_id})
		print("QA: choose game -> ", r.ok, " ", r.error)
	if str(t.get("desired")) != "running":
		r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"desired": "running"})
		print("QA: start -> ", r.ok, " ", r.error)
	await app.refresh(true)


## Admin pages (read-only screenshots; never acts on other users' tabs).
func _admin() -> void:
	var cred := _creds("LOCAL_LOGIN.txt")
	if cred.is_empty():
		return
	await _resize(Vector2i(1280, 800))
	var r: Dictionary = await app.api.request("/auth/login", Api.POST, cred)
	if not r.ok:
		print("QA: admin login failed: ", r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await app.enter_app()
	app.go("admin")
	await _wait(2.0)
	for s in ["overview", "orders", "jars", "users", "tabs", "audit", "content"]:
		app.page.section = s
		app.page.on_data()
		await _wait(1.5 if s == "content" else 0.5)
		await shot(out_dir + "/admin-%s.png" % s)
	app.logout()


func _resize(s: Vector2i) -> void:
	var win: Window = app.get_window()
	win.min_size = Vector2i(320, 320)
	win.size = s
	await _wait(0.9)


func _wait(sec: float) -> void:
	await app.get_tree().create_timer(sec).timeout


func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = app.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("QA: saved %s (%dx%d) err=%d" % [path.get_file(), img.get_width(), img.get_height(), err])


func _fail(msg: String) -> void:
	push_error("QA: " + msg)
	app.get_tree().quit(1)



## Phone viewer check: portrait 400×860 / 360×740 and landscape 860×400 / 740×360, plus a landscape game.
## Prints control bounds that fall outside the window and whether the stream object survived resizes.
func _viewer_sizes() -> void:
	await app.load_public()
	var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not r.ok:
		_fail("Đăng nhập QA thất bại: " + r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await _resize(Vector2i(400, 860))
	await app.enter_app()
	if app.tabs.is_empty():
		_fail("Tài khoản QA chưa có tab")
		return
	tab_id = str(app.tabs[0].id)
	await _ensure_game()
	var t0: Dictionary = app.tabs[0]
	if str(t0.get("screen", "240x320")) != "240x320":
		await app.api.request("/tabs/" + tab_id, Api.PATCH, {"screen": "240x320"})
		await app.refresh(true)
	app.go("viewer", {"id": tab_id})
	var waited := 0.0
	while waited < 40.0 and _frame_at_ok() == false:
		await _wait(1.0)
		waited += 1.0
	var src_id: int = app.page.source.get_instance_id()
	for sz in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1024, 768),
			Vector2i(400, 860), Vector2i(360, 740), Vector2i(860, 400), Vector2i(740, 360)]:
		await _resize(sz)
		await _wait(2.0)
		_report_clipping("%dx%d" % [sz.x, sz.y])
		var page_scroll: int = app.get("_scroll").get_v_scroll_bar().max_value - app.get("_scroll").size.y
		print("QA: %dx%d page needs scroll: %s" % [sz.x, sz.y, page_scroll > 1 and app.page._mode != "pad"])
		print("QA: %dx%d mode=%s stream_same=%s live=%s" % [sz.x, sz.y, app.page._mode, app.page.source.get_instance_id() == src_id, app.page.source.is_live()])
		await shot(out_dir + "/v-%dx%d.png" % [sz.x, sz.y])
	# Landscape game at phone-landscape size
	await _resize(Vector2i(860, 400))
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"screen": "320x240"})
	print("QA: rotate to 320x240 -> ", r.ok, " ", r.error)
	await app.refresh(true)
	app.page._begin_rotation("320x240")
	await _wait(1.0)
	await shot(out_dir + "/v-rotating-860x400.png")
	waited = 0.0
	while waited < 60.0 and not app.page._rotating_to.is_empty():
		await _wait(1.0)
		waited += 1.0
	await _wait(2.0)
	print("QA: rotation done after %.0fs (frame %s)" % [waited, str(app.page._frame_size())])
	_report_clipping("860x400-landscape")
	await shot(out_dir + "/v-landscape-game-860x400.png")
	await _resize(Vector2i(400, 860))
	await _wait(2.0)
	await shot(out_dir + "/v-landscape-game-400x860.png")
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"screen": "240x320"})
	print("QA: back to portrait -> ", r.ok)
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"desired": "stopped"})
	print("QA: stopped QA tab -> ", r.ok)


func _frame_at_ok() -> bool:
	return app.page_id == "viewer" and int(app.page.get("_last_frame_at")) > 0


## Lists visible buttons whose rect leaves the window (clipped controls).
## horizontal_only: scrolling pages may legitimately extend below the window; only sideways overflow counts.
func _report_clipping(tag: String, horizontal_only: bool = false) -> void:
	var win := Rect2(Vector2.ZERO, app.size)
	var bad: Array = []
	var stack: Array = [app]
	var scroll_skip: Node = null
	if app.modal_open():
		stack = [app.get("_modal_panel")]  # page behind the overlay doesn't count
		scroll_skip = app.get("_modal_scroll")  # dialog body may scroll internally
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == scroll_skip:
			continue
		for c in n.get_children():
			stack.append(c)
		if n is Button and (n as Control).is_visible_in_tree():
			var rect := (n as Control).get_global_rect()
			var out := rect.position.x < -1.0 or rect.end.x > win.size.x + 1.0 if horizontal_only else not win.encloses(rect.grow(-1.0))
			if rect.size.x > 0 and out and not (n as Control).get_parent() is ScrollContainer:
				bad.append("%s@%s" % [(n as Button).text, str(rect)])
	print("QA: clipping %s -> %d %s" % [tag, bad.size(), str(bad.slice(0, 6))])



const AUDIT_SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1024, 768),
	Vector2i(400, 860), Vector2i(360, 740), Vector2i(860, 400), Vector2i(740, 360)]


## Fixed layouts (login, dialogs) at every size: report clipped buttons; screenshots for review.
func _audit_sizes() -> void:
	await app.load_public()
	app.api.token = ""
	for sz in AUDIT_SIZES:
		await _resize(sz)
		app.go("login")
		await _wait(0.8)
		_report_clipping("login-%dx%d" % [sz.x, sz.y])
		await shot(out_dir + "/a-login-%dx%d.png" % [sz.x, sz.y])
	var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not r.ok:
		_fail("Đăng nhập QA thất bại: " + r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await app.enter_app()
	tab_id = str(app.tabs[0].id) if not app.tabs.is_empty() else ""
	for sz in AUDIT_SIZES:
		await _resize(sz)
		var tag := "%dx%d" % [sz.x, sz.y]
		app.go("tabs")
		await _wait(1.0)
		Actions.rent(app)
		await _wait(1.2)
		_report_clipping("rent-" + tag)
		await shot(out_dir + "/a-rent-%s.png" % tag)
		app.close_modal()
		for t in app.tabs:
			if str(t.id) == tab_id:
				Actions.change_game(app, t)
		await _wait(1.2)
		_report_clipping("change-game-" + tag)
		await shot(out_dir + "/a-change-game-%s.png" % tag)
		app.close_modal()
		app.go("settings")
		await _wait(1.0)
		_report_clipping("settings-" + tag, true)
		await shot(out_dir + "/a-settings-%s.png" % tag)



## Only the four docs/ screenshots, with a single login (the API rate-limits logins per IP).
func _docs_only(docs: String) -> void:
	await _resize(Vector2i(1280, 800))
	await app.load_public()
	app.api.token = ""
	app.go("login")
	await _wait(1.2)
	await shot(docs + "/godot-login.png")
	var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not r.ok:
		_fail("Đăng nhập QA thất bại: " + r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await app.enter_app()
	tab_id = str(app.tabs[0].id)
	await _ensure_game()
	app.go("tabs")
	var waited := 0.0
	while waited < 60.0 and _state() != "running":
		await _wait(1.0)
		waited += 1.0
	await _wait(TK.poll("wall") * 3.0)
	await shot(docs + "/godot-dashboard.png")
	app.go("viewer", {"id": tab_id})
	waited = 0.0
	while waited < 30.0 and not app.page.source.is_live():
		await _wait(0.5)
		waited += 0.5
	await app.page.send("5")
	await _wait(2.5)
	_report_clipping("docs-viewer-1280x800")
	await shot(docs + "/godot-nokia.png")
	await _resize(Vector2i(400, 860))
	app.go("tabs")
	await _wait(2.5)
	await shot(docs + "/godot-mobile.png")
	app.go("viewer", {"id": tab_id})
	await _wait(3.0)
	await shot(out_dir + "/docs-viewer-400x860.png")
	await _resize(Vector2i(860, 400))
	await _wait(3.0)
	await shot(out_dir + "/docs-viewer-860x400.png")
	# Touch mode (virtual keys hidden) + stretched game, in landscape, desktop and portrait.
	app.page._toggle_pad()
	app.page._toggle_stretch()
	await _wait(1.5)
	print("QA: touch 860x400 stack=%s pad_root=%s" % [app.page._stack.size, app.page._pad_root.size])
	await shot(out_dir + "/docs-viewer-860x400-touch.png")
	await _resize(Vector2i(1280, 800))
	await _wait(2.0)
	_report_clipping("viewer-touch-1280x800")
	await shot(out_dir + "/docs-viewer-1280x800-touch.png")
	await _resize(Vector2i(400, 860))
	await _wait(2.0)
	await shot(out_dir + "/docs-viewer-400x860-touch.png")
	app.page._toggle_pad()
	app.page._toggle_stretch()
	r = await app.api.request("/tabs/" + tab_id, Api.PATCH, {"desired": "stopped"})
	print("QA: stopped QA tab -> ", r.ok)



## Growth/support round: every new page and dialog at 1280×800 and 400×860 (+ viewer 860×400).
## Uses one admin and one user login (tokens are swapped), unique "Godot QA" names, and deletes the
## test coupon/share it creates. Maintenance is shown through a local config override only.
func _growth_round() -> void:
	const COUPON := "GODOTQA10"
	await app.load_public()
	var ra: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("LOCAL_LOGIN.txt"))
	var ru: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not ra.ok or not ru.ok:
		_fail("Đăng nhập thất bại: %s %s" % [ra.error, ru.error])
		return
	var admin_tok := str(ra.data.token)
	var user_tok := str(ru.data.token)
	# Admin prepares a unique test coupon.
	app.api.token = admin_tok
	var rc: Dictionary = await app.api.request("/admin/coupons", Api.POST, {"code": COUPON, "kind": "percent", "value": 10, "max_value": 0,
		"min_amount": 0, "max_uses": 0, "per_user": 5, "expires": 0, "active": true, "note": "Godot QA – xoá sau khi kiểm thử"})
	print("QA: create coupon -> ", rc.ok, " ", rc.error)
	if int(ru.data.user.get("balance", 0)) < 3000:
		var rb: Dictionary = await app.api.request("/admin/users/%s/balance" % str(ru.data.user.id), Api.POST, {"amount": 20000, "reason": "Godot QA kiểm thử"})
		print("QA: top up QA account -> ", rb.ok, " ", rb.error)

	# ---- user
	app.api.token = user_tok
	app.user = ru.data.user
	await app.enter_app()
	var mine := ""
	for t in app.tabs:
		if str(t.name).begins_with("Godot QA"):
			mine = str(t.id)
	if mine.is_empty():
		var r: Dictionary = await app.api.request("/tabs", Api.POST, {"name": "Godot QA tab", "plan": "day", "coupon": COUPON})
		print("QA: rent with coupon -> ", r.ok, " ", r.error)
		mine = str(r.data.get("id", "")) if r.ok else ""
		await app.refresh(true)
	tab_id = mine
	if tab_id.is_empty():
		_fail("Không có tab QA")
		return
	await app.api.request("/tabs/%s/schedule" % tab_id, Api.PATCH, {"group": "Godot QA nhóm", "restart_at": "04:30"})
	var rt: Dictionary = await app.api.request("/tickets", Api.POST, {"subject": "Godot QA – kiểm tra hỗ trợ", "body": "Tin nhắn thử từ ứng dụng Godot (QA)."})
	var ticket_id := str(rt.data.get("id", "")) if rt.ok else ""
	await app.refresh(true)
	await app.load_notifications()

	for sz in [Vector2i(1280, 800), Vector2i(400, 860)]:
		await _resize(sz)
		var tag := "%dx%d" % [sz.x, sz.y]
		var tab: Dictionary = {}
		for t in app.tabs:
			if str(t.id) == tab_id:
				tab = t
		app.go("tabs")
		await _wait(2.0)
		_report_clipping("tabs-" + tag, true)
		await shot(out_dir + "/g-tabs-%s.png" % tag)
		app.page.selecting = true
		app.page.selected[tab_id] = true
		app.page._refresh_cards()
		await _wait(0.8)
		_report_clipping("tabs-select-" + tag, true)
		await shot(out_dir + "/g-tabs-select-%s.png" % tag)
		app.page.selecting = false
		app.page.selected.clear()
		app.page._refresh_cards()
		for d in [["notifications", func() -> void: app.open_notifications()],
				["rent", func() -> void: Actions.rent(app)],
				["renew", func() -> void: Actions.renew(app, tab, false)],
				["group", func() -> void: Actions.group_dialog(app, tab)],
				["schedule", func() -> void: Actions.schedule_dialog(app, tab)],
				["share", func() -> void: Actions.share_dialog(app, tab)]]:
			d[1].call()
			await _wait(1.5)
			if d[0] in ["rent", "renew"]:
				_fill_coupon(COUPON)
				await _wait(1.5)
			_report_clipping(d[0] + "-" + tag)
			await shot(out_dir + "/g-%s-%s.png" % [d[0], tag])
			app.close_modal()
		for p in ["support", "referral", "account", "wallet", "plans"]:
			app.go(p)
			await _wait(1.8)
			_report_clipping(p + "-" + tag, true)
			await shot(out_dir + "/g-%s-%s.png" % [p, tag])
		if not ticket_id.is_empty():
			app.go("support", {"id": ticket_id})
			await _wait(1.8)
			_report_clipping("ticket-" + tag, true)
			await shot(out_dir + "/g-ticket-%s.png" % tag)
		# Maintenance banner (local override only)
		var cfg_m: Variant = app.config.get("maintenance", {})
		app.config["maintenance"] = {"enabled": true, "message": "Bảo trì nâng cấp máy chủ (QA, chỉ hiển thị cục bộ).", "until": UI_now() + 3600}
		app.go("tabs")
		await _wait(1.5)
		await shot(out_dir + "/g-maintenance-%s.png" % tag)
		app.config["maintenance"] = cfg_m
		app.call("_render_announcement")
	# Viewer with latency readout, phone landscape (the QA tab gets the fixture game first)
	await app.refresh(true)
	var qi := -1
	for i in app.tabs.size():
		if str(app.tabs[i].id) == tab_id:
			qi = i
	if qi > 0:
		var tmp: Dictionary = app.tabs[0]
		app.tabs[0] = app.tabs[qi]
		app.tabs[qi] = tmp
	await _ensure_game()
	await _resize(Vector2i(860, 400))
	app.go("viewer", {"id": tab_id})
	var waited := 0.0
	while waited < 75.0 and app.page_id == "viewer" and not app.page.source.is_live():
		await _wait(1.0)
		waited += 1.0
	if app.page_id != "viewer":
		print("QA: left viewer unexpectedly (page=%s)" % app.page_id)
		app.go("viewer", {"id": tab_id})
		await _wait(8.0)
	await _wait(5.0)
	print("QA: viewer live after %.0fs, readout = %s" % [waited, app.page._readout.text])
	_report_clipping("viewer-860x400")
	await shot(out_dir + "/g-viewer-860x400.png")
	await _resize(Vector2i(1280, 800))
	await _wait(3.0)
	print("QA: viewer readout desktop = ", app.page._readout.text)
	await shot(out_dir + "/g-viewer-1280x800.png")
	# Clean up the user's own share links; stop the QA tab.
	var rs: Dictionary = await app.api.request("/tabs/%s/shares" % tab_id)
	if rs.ok:
		for sh in rs.data:
			await app.api.request("/tabs/%s/shares/%s" % [tab_id, str(sh.token)], Api.DELETE)
	await app.api.request("/tabs/" + tab_id, Api.PATCH, {"desired": "stopped"})

	# ---- admin
	app.api.token = admin_tok
	app.user = ra.data.user
	await app.enter_app()
	for sz in [Vector2i(1280, 800), Vector2i(400, 860)]:
		await _resize(sz)
		var tag := "%dx%d" % [sz.x, sz.y]
		for sec in ["support", "coupons", "growth"]:
			app.go("admin", {"section": sec})
			await _wait(2.5)
			_report_clipping("admin-%s-%s" % [sec, tag], true)
			await shot(out_dir + "/g-admin-%s-%s.png" % [sec, tag])
		if not ticket_id.is_empty():
			app.go("support", {"id": ticket_id, "admin": true})
			await _wait(1.5)
			await shot(out_dir + "/g-admin-ticket-%s.png" % tag)
	if not ticket_id.is_empty():
		var rr: Dictionary = await app.api.request("/tickets/%s/messages" % ticket_id, Api.POST, {"body": "Phản hồi thử từ quản trị (Godot QA)."})
		print("QA: staff reply -> ", rr.ok)
		await app.api.request("/tickets/%s/close" % ticket_id, Api.POST)
	var rd: Dictionary = await app.api.request("/admin/coupons/" + COUPON, Api.DELETE)
	print("QA: delete coupon -> ", rd.ok, " ", rd.error)
	app.api.token = ""
	print("QA: growth round done")


func UI_now() -> int:
	return int(Time.get_unix_time_from_system())


## Types the coupon into the open dialog's "Mã khuyến mãi" box and presses "Áp dụng".
func _fill_coupon(code: String) -> void:
	var stack: Array = [app.get("_modal_panel")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with("Nhập mã"):
			(n as LineEdit).text = code
			(n as LineEdit).text_submitted.emit(code)
			return



## Prints the deepest controls whose minimum width exceeds the window (what forces horizontal overflow).
func _print_wide(root: Node, limit: float) -> void:
	var stack: Array = [root]
	var found: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Control and (n as Control).get_combined_minimum_size().x > limit - 40.0:
			var deeper := false
			for c in n.get_children():
				if c is Control and (c as Control).get_combined_minimum_size().x > limit - 40.0:
					deeper = true
			if not deeper:
				found.append("%s(%s) min=%s text=%s" % [n.get_class(), (n as Control).theme_type_variation, str((n as Control).get_combined_minimum_size()), str(n.get("text")).left(40)])
	print("QA: wide in %s -> %s" % [app.page_id, str(found.slice(0, 8))])



## Component polish check: dialogs, toast stack, notifications popover, menus and banners at
## 1280×800 and 400×860 in dark + light. Theme is switched locally only (the QA account is shared).
func _polish_round() -> void:
	await app.load_public()
	var r: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	if not r.ok:
		_fail("Đăng nhập QA thất bại: " + r.error)
		return
	app.api.token = str(r.data.token)
	app.user = r.data.user
	await _resize(Vector2i(1280, 800))
	await app.enter_app()
	await app.load_notifications()
	var tab: Dictionary = {}
	for t in app.tabs:
		if str(t.name).begins_with("Godot QA"):
			tab = t
	if tab.is_empty() and not app.tabs.is_empty():
		tab = app.tabs[0]
	var issues := 0
	for theme_id in ["dark", "light"]:
		app.pref_override = {"theme": theme_id}  # local only: the QA account's synced prefs stay untouched
		app.apply_prefs()
		for sz in [Vector2i(1280, 800), Vector2i(400, 860)]:
			await _resize(sz)
			var tag := "%s-%dx%d" % [theme_id, sz.x, sz.y]
			app.go("tabs")
			await _wait(1.5)
			var dialogs := [
				["rent", func() -> void: Actions.rent(app)],
				["renew", func() -> void: Actions.renew(app, tab, false)],
				["rename", func() -> void: Actions.rename(app, tab)],
				["change-game", func() -> void: Actions.change_game(app, tab)],
				["screen", func() -> void: Actions.pick_screen(app, tab)],
				["share", func() -> void: Actions.share_dialog(app, tab)],
				["group", func() -> void: Actions.group_dialog(app, tab)],
				["schedule", func() -> void: Actions.schedule_dialog(app, tab)],
				["logs", func() -> void: Actions.logs(app, tab)],
				["confirm", func() -> void: app.confirm("Giải phóng tab", "Xóa tab \"%s\" khỏi tài khoản? Slot đã trả tiền vẫn được giữ." % str(tab.get("name", "")), "Giải phóng", Callable(), true)],
			]
			for d in dialogs:
				d[1].call()
				await _wait(1.3)
				issues += _check_dialog("%s-%s" % [d[0], tag])
				issues += _check_buttons("%s-%s" % [d[0], tag], app.get("_modal_panel"))
				await shot(out_dir + "/p-%s-%s.png" % [d[0], tag])
				app.close_modal()
			# Notifications: popover on desktop, full-screen sheet on phones
			app.open_notifications()
			await _wait(0.8)
			await shot(out_dir + "/p-notifications-%s.png" % tag)
			app.call("_close_popover")
			app.close_modal()
			# Toast stack (3 kinds) + banners (local overrides only)
			var cfg_m: Variant = app.config.get("maintenance", {})
			var site: Dictionary = app.config.get("site", {}).duplicate()
			app.config["maintenance"] = {"enabled": true, "message": "Nâng cấp hệ thống (QA, chỉ hiển thị cục bộ).", "until": 0}
			var s2 := site.duplicate()
			s2["announcement"] = "Ưu đãi cuối tuần: giảm 10% khi thuê gói 30 ngày (QA)."
			app.config["site"] = s2
			app.call("_render_announcement")
			app.toast("Đã gửi lệnh chạy: Godot QA tab")
			await _wait(0.1)
			app.toast("Đang khởi động lại tab…", false, "info")
			await _wait(0.1)
			app.toast("Số dư không đủ. Hãy nạp thêm tiền vào ví.", true)
			await _wait(0.6)
			await shot(out_dir + "/p-toasts-banners-%s.png" % tag)
			app.config["maintenance"] = cfg_m
			app.config["site"] = site
			app.call("_render_announcement")
			# Menu: the tab card overflow menu
			var menu := _find_menu(app.page)
			if menu:
				var pop: Control = UIH.open_menu(menu)
				await _wait(0.5)
				await shot(out_dir + "/p-menu-%s.png" % tag)
				pop.call("close")
			issues += _check_buttons("page-tabs-" + tag, app.page)
			await _wait(4.0)  # let toasts expire
	app.pref_override = {}
	print("QA: polish done, issues=%d" % issues)


func _find_menu(root: Node) -> Button:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button and n.has_meta("menu_items") and (n as Button).text == "⋯" and (n as Control).is_visible_in_tree():
			return n
	return null


## Dialogs must be centred (equal side margins ±1 px) on desktop, or a full-width bottom sheet.
func _check_dialog(tag: String) -> int:
	var p: Control = app.get("_modal_panel")
	var left := p.position.x
	var right: float = app.size.x - (p.position.x + p.size.x)
	var ok: bool
	if app.sheet_mode():
		ok = absf(left) <= 1.0 and absf(right) <= 1.0 and absf(p.position.y + p.size.y - app.size.y) <= 1.0
	else:
		var top := p.position.y
		var bottom: float = app.size.y - (p.position.y + p.size.y)
		ok = absf(left - right) <= 1.0 and absf(top - bottom) <= 1.0
	if not ok:
		print("QA: dialog not centred %s: left=%.1f right=%.1f y=%.1f h=%.1f" % [tag, left, right, p.position.y, p.size.y])
	return 0 if ok else 1


## Text buttons must use a token height: sm/md/lg (desktop) or ≥ touch_min on touch layouts.
func _check_buttons(tag: String, root: Node) -> int:
	var T2 := preload("res://native/tokens.gd")
	var allowed: Array = [T2.compf("button.sm.height", 32), T2.compf("button.md.height", 40), T2.compf("button.lg.height", 48)]
	var touch_min := T2.compf("button.touch_min", 44)
	var bad: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Button) or n is CheckBox or n is OptionButton or not (n as Control).is_visible_in_tree():
			continue
		var b := n as Button
		if b.text.strip_edges().is_empty() or b.theme_type_variation in ["KeyButton", "NavButton", "NavButtonActive", "BottomNavButton", "BottomNavButtonActive"]:
			continue
		var h := b.size.y
		var ok := false
		if UIH.touch:
			ok = h >= touch_min - 0.5
		else:
			for a in allowed:
				if absf(h - a) <= 0.5:
					ok = true
		if not ok:
			bad.append("%s=%.0f" % [b.text.left(18), h])
	if not bad.is_empty():
		print("QA: button heights %s -> %s" % [tag, str(bad.slice(0, 6))])
	return 0 if bad.is_empty() else 1



## Custom overflow menus: card, viewer, account and admin menus at 1280×800 / 400×860, dark + light.
## Also checks keyboard navigation (↓ moves focus, Esc closes).
func _menus_round() -> void:
	await app.load_public()
	var ru: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("QA_LOGIN.txt"))
	var ra: Dictionary = await app.api.request("/auth/login", Api.POST, _creds("LOCAL_LOGIN.txt"))
	if not ru.ok:
		_fail("Đăng nhập QA thất bại: " + ru.error)
		return
	app.api.token = str(ru.data.token)
	app.user = ru.data.user
	var r: Dictionary = await app.api.request("/tabs", Api.POST, {"name": "Godot QA menu", "plan": "day"})
	print("QA: rent -> ", r.ok, " ", r.error)
	tab_id = str(r.data.get("id", "")) if r.ok else ""
	await _resize(Vector2i(1280, 800))
	await app.enter_app()
	for theme_id in ["dark", "light"]:
		app.pref_override = {"theme": theme_id}
		app.apply_prefs()
		for sz in [Vector2i(1280, 800), Vector2i(400, 860)]:
			await _resize(sz)
			var tag := "%s-%dx%d" % [theme_id, sz.x, sz.y]
			app.go("tabs")
			await _wait(1.5)
			var card_menu := _find_menu(app.page)
			if card_menu:
				var pop: Control = UIH.open_menu(card_menu)
				await _wait(0.4)
				if theme_id == "dark" and sz.x == 1280:
					var f0 := app.get_viewport().gui_get_focus_owner()
					var ev := InputEventAction.new()
					ev.action = "ui_down"
					ev.pressed = true
					Input.parse_input_event(ev)
					await _wait(0.2)
					var f1 := app.get_viewport().gui_get_focus_owner()
					print("QA: keyboard focus moved=%s" % [f0 != f1 and f1 != null])
				await shot(out_dir + "/m-card-%s.png" % tag)
				if is_instance_valid(pop):
					pop.call("close")
			# account menu in the header
			var acc := _find_menu_text(app, "Tài khoản") if sz.x < 640 else _find_menu_text(app, str(app.user.get("name", "")))
			if acc:
				var pop2: Control = UIH.open_menu(acc)
				await _wait(0.4)
				await shot(out_dir + "/m-account-%s.png" % tag)
				var esc := InputEventAction.new()
				esc.action = "ui_cancel"
				esc.pressed = true
				Input.parse_input_event(esc)
				await _wait(0.2)
				if theme_id == "dark" and sz.x == 1280:
					print("QA: esc closes menu=%s" % [not is_instance_valid(pop2) or pop2.is_queued_for_deletion()])
			if not tab_id.is_empty():
				app.go("viewer", {"id": tab_id})
				await _wait(1.5)
				var vm := _find_menu(app.page)
				if vm == null:
					vm = _find_menu(app.page_overlay)
				if vm:
					var pop3: Control = UIH.open_menu(vm)
					await _wait(0.4)
					await shot(out_dir + "/m-viewer-%s.png" % tag)
					pop3.call("close")
	if ra.ok:
		app.api.token = str(ra.data.token)
		app.user = ra.data.user
		await app.enter_app()
		for theme_id in ["dark", "light"]:
			app.pref_override = {"theme": theme_id}
			app.apply_prefs()
			for sz in [Vector2i(1280, 800), Vector2i(400, 860)]:
				await _resize(sz)
				app.go("admin", {"section": "users"})
				await _wait(2.0)
				var am := _find_menu(app.page)
				if am:
					var pop4: Control = UIH.open_menu(am)
					await _wait(0.4)
					await shot(out_dir + "/m-admin-users-%s-%dx%d.png" % [theme_id, sz.x, sz.y])
					pop4.call("close")
	app.pref_override = {}
	print("QA: menus done")


func _find_menu_text(root: Node, prefix: String) -> Button:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button and n.has_meta("menu_items") and (n as Button).text.begins_with(prefix) and (n as Control).is_visible_in_tree():
			return n
	return null
