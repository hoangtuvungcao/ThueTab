extends "res://native/pages/page.gd"
## "File JAR": upload (native file dialog), list with J2ME / Java PC kind and review status.

const Actions := preload("res://native/pages/tab_actions.gd")

var _list: VBoxContainer


func needs() -> Array:
	return ["jars"]


func auto_approve() -> bool:
	return bool(app.config.get("jar_auto_approve", true))


func build() -> void:
	var up := UI.card(self, "Card", T.space("md"))
	UI.label(up, "Tải lên file .jar", "SubheadingLabel")
	var max_mb := int(app.config.get("jar_max_mb", 30))
	var text := "Hỗ trợ game J2ME (điện thoại Nokia) và Java PC, tối đa %d MB. " % max_mb
	if auto_approve():
		text += "File dùng được ngay và chạy trong môi trường riêng, an toàn."
	else:
		text += "File được duyệt trước khi chạy, trong môi trường riêng, an toàn."
	UI.label(up, text, "BodyMutedLabel")
	UI.label(up, "Sau khi tải lên, bấm \"Đổi game\" trên một tab để chạy file — hoặc thuê tab mới với file này.", "MutedLabel")
	var row := UI.flow(up)
	var pick := UI.button(row, "Chọn file .jar…", func() -> void: Actions.pick_and_upload(app), "PrimaryButton")
	pick.disabled = app.maintenance_on()
	if pick.disabled:
		UI.label(up, "Đang bảo trì — tạm thời chưa tải file lên được.", "DangerLabel")

	UI.label(self, "File của bạn", "SubheadingLabel")
	_list = UI.vbox(self, T.space("sm"))
	render()


func signature() -> Variant:
	return [app.jars, app.tabs.map(func(t: Dictionary) -> Variant: return [t.name, t.get("custom_jar_id")]), app.content_width()]


func render() -> void:
	UI.clear(_list)
	if app.jars.is_empty():
		UI.empty_state(_list, "Chưa có file JAR", "Tải lên bản game Java (.jar) của bạn để chạy trong tab riêng.")
		return
	var grid := GridContainer.new()
	grid.columns = columns_for(420.0)
	grid.add_theme_constant_override("h_separation", T.space("md"))
	grid.add_theme_constant_override("v_separation", T.space("md"))
	_list.add_child(grid)
	_pager(_list, "jars", app.jars.size(), 10)
	for j in _page_of("jars", app.jars, 10):
		var c := UI.card(grid, "Card", T.space("sm"))
		var top := UI.hbox(c, T.space("md"))
		UI.image(top, UI.game_icon("custom"), Vector2(40, 40))
		var titles := UI.vbox(top, 2)
		titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI.label_clip(titles, str(j.filename), "StrongLabel")
		UI.label_clip(titles, "%s · tải lên %s" % [UI.file_size(j.get("file_size", 0)), UI.datetime(j.get("created"))], "MutedLabel")
		var badges := UI.vbox(top, T.space("xs"))
		badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		Actions.kind_badge(badges, str(j.get("kind", ""))).size_flags_horizontal = Control.SIZE_SHRINK_END
		var st := str(j.get("status", "approved"))
		if st != "approved" or not auto_approve():
			UI.jar_badge(badges, st).size_flags_horizontal = Control.SIZE_SHRINK_END
		var users: Array = []
		for t in app.tabs:
			if t.get("custom_jar_id") != null and str(t.custom_jar_id) == str(j.id):
				users.append(str(t.name))
		if not users.is_empty():
			UI.label(c, "Đang dùng ở: " + ", ".join(PackedStringArray(users)), "MutedLabel")
		if st == "rejected":
			UI.label(c, "File bị từ chối nên không thể chạy.", "DangerLabel")
		elif st == "pending":
			UI.label(c, "Đang chờ quản trị viên duyệt.", "MutedLabel")
		var actions := UI.flow(c)
		var rent := UI.button(actions, "Thuê tab với file này", func() -> void: Actions.rent(app, str(j.id)), "")
		rent.disabled = st != "approved"
		UI.button(actions, "Đổi tên", func() -> void: Actions.rename_jar(app, j), "")
		UI.button(actions, "Xóa", func() -> void:
			app.confirm("Xóa file JAR", "Xóa \"%s\"? Không thể xóa khi còn tab đang dùng file này." % str(j.filename), "Xóa", func() -> void:
				await app.act("/jars/" + str(j.id), Api.DELETE, null, "Đã xóa file JAR."), true), "DangerButton")
