extends "res://native/pages/page.gd"
## "Giới thiệu bạn bè": personal code + link, reward rules, invited friends and earnings (GET /me/referral).

var _box: VBoxContainer


func build() -> void:
	_box = UI.vbox(self, T.space("lg"))
	UI.label(_box, "Đang tải…", "MutedLabel")
	var r: Dictionary = await app.api.request("/me/referral")
	if not is_instance_valid(_box):
		return
	UI.clear(_box)
	if not r.ok:
		UI.label(_box, r.error, "DangerLabel")
		return
	var d: Dictionary = r.data
	if not bool(d.get("enabled", true)):
		UI.empty_state(_box, "Chương trình giới thiệu đang tạm dừng", "Vui lòng quay lại sau.")
		return
	var link: String = str(app.api.endpoint) + str(d.get("path", "/#/register?ref=" + str(d.get("code", ""))))

	var top := GridContainer.new()
	top.columns = 1 if app.content_width() < 760 else 2
	top.add_theme_constant_override("h_separation", T.space("lg"))
	top.add_theme_constant_override("v_separation", T.space("lg"))
	_box.add_child(top)

	var share := UI.card(top, "CardAccent", T.space("md"))
	UI.label(share, "Mã giới thiệu của bạn", "MutedLabel")
	var code_row := UI.hbox(share, T.space("sm"))
	var code := UI.label(code_row, str(d.get("code", "")), "TitleLabel", false)
	code.add_theme_color_override("font_color", T.accent_text())
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.button(code_row, "Sao chép mã", func() -> void:
		DisplayServer.clipboard_set(str(d.get("code", "")))
		app.toast("Đã sao chép mã giới thiệu."), "")
	UI.label(share, "Gửi liên kết đăng ký có sẵn mã của bạn:", "MutedLabel")
	var copy_link := UI.button(share, "Sao chép liên kết mời", func() -> void:
		DisplayServer.clipboard_set(link)
		app.toast("Đã sao chép liên kết mời."), "PrimaryButton")
	copy_link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var rules := UI.card(top, "Card", T.space("sm"))
	UI.label(rules, "Cách nhận thưởng", "SubheadingLabel")
	var pct := int(d.get("percent", 0))
	var cap := int(d.get("max_bonus", 0))
	UI.label(rules, "Khi bạn bè đăng ký bằng mã của bạn và nạp tiền lần đầu, bạn nhận %d%% số tiền nạp đó vào ví%s." % [pct, (" (tối đa %s mỗi người)" % UI.money(cap)) if cap > 0 else ""], "BodyMutedLabel")
	UI.label(rules, "Gửi liên kết cho bạn bè hoặc nhờ họ nhập mã ở ô \"Mã giới thiệu\" khi tạo tài khoản.", "MutedLabel")

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", T.space("md"))
	stats.add_theme_constant_override("v_separation", T.space("md"))
	_box.add_child(stats)
	UI.stat(stats, "Đã mời", str(int(d.get("invited", 0))))
	UI.stat(stats, "Đã nhận", UI.money(d.get("earned", 0)))

	UI.label(_box, "Bạn bè đã mời", "SubheadingLabel")
	var friends: Array = d.get("friends", [])
	if friends.is_empty():
		UI.label(_box, "Chưa có ai đăng ký bằng mã của bạn.", "MutedLabel")
		return
	var c := UI.card(_box, "Card", T.space("xs"))
	for i in friends.size():
		if i > 0:
			UI.separator(c)
		var row := UI.hbox(c, T.space("md"))
		UI.label_clip(row, str(friends[i].get("name", "")), "StrongLabel")
		UI.label(row, UI.datetime(friends[i].get("created")), "DimLabel", false)
