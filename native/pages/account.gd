extends "res://native/pages/page.gd"
## "Tài khoản": profile name, password change, sign out (this device / all devices).


func build() -> void:
	var u: Dictionary = app.user
	var grid := GridContainer.new()
	grid.columns = 1 if app.content_width() < 720 else 2
	grid.add_theme_constant_override("h_separation", T.space("md"))
	grid.add_theme_constant_override("v_separation", T.space("md"))
	add_child(grid)

	var prof := UI.card(grid, "Card", T.space("md"))
	prof.get_parent().size_flags_vertical = Control.SIZE_FILL
	UI.label(prof, "Hồ sơ", "SubheadingLabel")
	var info := UI.card(prof, "CardInset", T.space("xs"))
	_row(info, "Email", str(u.get("email", "")))
	_row(info, "Vai trò", "Quản trị viên" if app.is_admin() else "Người dùng")
	_row(info, "Ngày tạo", UI.datetime(u.get("created")))
	_row(info, "Số dư", UI.money(u.get("balance", 0)))
	var name_in := UI.field(prof, "Tên hiển thị", "Tên của bạn")
	name_in.text = str(u.get("name", ""))
	name_in.max_length = 60
	var save := UI.button(prof, "Lưu tên", Callable(), "PrimaryButton")
	save.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.on_press(save, func() -> void:
		var n := name_in.text.strip_edges()
		if n.is_empty():
			app.toast("Tên không được để trống.", true)
			return
		var r: Dictionary = await app.api.request("/me", Api.PATCH, {"name": n})
		if r.ok:
			app.user = r.data if r.data is Dictionary and r.data.has("email") else app.user
			app.toast("Đã lưu tên hiển thị.")
			await app.refresh()
		else:
			app.toast(r.error, true))

	var pw := UI.card(grid, "Card", T.space("md"))
	UI.label(pw, "Đổi mật khẩu", "SubheadingLabel")
	UI.label(pw, "Đổi mật khẩu sẽ đăng xuất các thiết bị khác.", "MutedLabel")
	var old_in := UI.field(pw, "Mật khẩu hiện tại", "", true)
	var new_in := UI.field(pw, "Mật khẩu mới (tối thiểu 10 ký tự)", "", true)
	var again_in := UI.field(pw, "Nhập lại mật khẩu mới", "", true)
	var change := UI.button(pw, "Đổi mật khẩu", Callable(), "PrimaryButton")
	change.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	change.pressed.connect(func() -> void:
		if new_in.text.length() < 10:
			app.toast("Mật khẩu mới cần tối thiểu 10 ký tự.", true)
			return
		if new_in.text != again_in.text:
			app.toast("Hai mật khẩu mới không khớp.", true)
			return
		change.disabled = true
		var r: Dictionary = await app.api.request("/me/password", Api.POST, {"old": old_in.text, "new": new_in.text})
		if is_instance_valid(change):
			change.disabled = false
		if r.ok:
			if r.data is Dictionary and r.data.has("token"):
				app.api.token = str(r.data.token)
				app.save_settings()
			for f in [old_in, new_in, again_in]:
				if is_instance_valid(f):
					f.clear()
			app.toast("Đã đổi mật khẩu.")
		else:
			app.toast(r.error, true))

	var sess := UI.card(self, "Card", T.space("md"))
	UI.label(sess, "Thiết bị đăng nhập", "SubheadingLabel")
	UI.label(sess, "Các thiết bị đang đăng nhập tài khoản này. Đăng xuất thiết bị bạn không nhận ra.", "MutedLabel")
	_devices = UI.vbox(sess, T.space("xs"))
	_load_devices()
	var row := UI.flow(sess)
	UI.button(row, "Đăng xuất", app.logout)
	UI.button(row, "Đăng xuất mọi thiết bị", func() -> void:
		app.confirm("Đăng xuất mọi thiết bị", "Mọi phiên đăng nhập (kể cả thiết bị này) sẽ bị đăng xuất. Tab vẫn tiếp tục chạy.", "Đăng xuất tất cả", app.logout_all, true), "DangerButton")


var _devices: VBoxContainer


func _load_devices() -> void:
	UI.clear(_devices)
	var r: Dictionary = await app.api.request("/me/sessions")
	if not is_instance_valid(_devices):
		return
	UI.clear(_devices)
	if not r.ok:
		UI.label(_devices, r.error, "DangerLabel")
		return
	var items: Array = r.data if r.data is Array else []
	for i in items.size():
		var d: Dictionary = items[i]
		if i > 0:
			UI.separator(_devices)
		var row := UI.hbox(_devices, T.space("md"))
		var col := UI.vbox(row, 0)
		UI.label_clip(col, device_name(str(d.get("agent", ""))), "StrongLabel").tooltip_text = str(d.get("agent", ""))
		UI.label_clip(col, "Đăng nhập %s" % UI.datetime(d.get("created")), "DimLabel")
		if d.get("current", false):
			UI.badge(row, "Thiết bị này", T.color("success"))
		else:
			var sid := str(d.id)
			UI.button(row, "Đăng xuất", func() -> void:
				var res: Dictionary = await app.api.request("/me/sessions/" + sid, Api.DELETE)
				if res.ok:
					app.toast("Đã đăng xuất thiết bị.")
					_load_devices()
				else:
					app.toast(res.error, true), "GhostButton")


## Turns a User-Agent into a friendly label, e.g. "Chrome trên Windows", "Ứng dụng ThuêTab · Android".
static func device_name(agent: String) -> String:
	var a := agent.to_lower()
	if a.is_empty():
		return "Thiết bị không rõ"
	var os_name := ""
	for pair in [["android", "Android"], ["iphone", "iPhone"], ["ipad", "iPad"], ["windows", "Windows"], ["mac os", "macOS"], ["macos", "macOS"], ["linux", "Linux"]]:
		if a.contains(pair[0]):
			os_name = pair[1]
			break
	if a.begins_with("thuetab-app") or a.contains("godot"):
		return "Ứng dụng " + T.brand("name") + (" · " + os_name if not os_name.is_empty() else "")
	var browser := "Trình duyệt"
	for pair in [["edg/", "Edge"], ["opr/", "Opera"], ["firefox", "Firefox"], ["chrome", "Chrome"], ["safari", "Safari"]]:
		if a.contains(pair[0]):
			browser = pair[1]
			break
	return browser + (" trên " + os_name if not os_name.is_empty() else "")


func _row(parent: Node, key: String, value: String) -> void:
	var r := UI.hbox(parent, T.space("sm"))
	var k := UI.label(r, key, "MutedLabel", false)
	k.custom_minimum_size.x = 90
	UI.label_clip(r, value, "")
