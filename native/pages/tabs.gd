extends "res://native/pages/page.gd"
## "Tab của tôi": one primary action (+ Thuê tab), status filter, and tab cards with a live thumbnail,
## a single primary button per card ("Chơi" / "Chọn game" / "Gia hạn") and an overflow menu.

const Actions := preload("res://native/pages/tab_actions.gd")
const FILTERS := ["all", "running", "queued", "idle", "stopping", "stopped", "expired", "error"]

var filter: String = "all"
var group_filter: String = ""  # "" = all groups, "__none__" = no group, else a group name
var selecting: bool = false
var selected: Dictionary = {}  # tab id -> true
var _batch: PanelContainer
var _bar: HBoxContainer
var _notice: VBoxContainer
var _filters: HFlowContainer
var _list: VBoxContainer
var _chrome_sig: String = ""
var _layout_sig: String = ""
var _slots_by_id: Dictionary = {}  # tab id -> slot Control holding that tab's card
var _card_sigs: Dictionary = {}  # tab id -> signature of the data shown on its card


func needs() -> Array:
	return ["slots", "jars"]


func build() -> void:
	add_theme_constant_override("separation", T.space("lg"))
	_bar = UI.hbox(self, T.space("sm"))
	_notice = UI.vbox(self, T.space("sm"))
	_batch = PanelContainer.new()
	_batch.theme_type_variation = "CardInset"
	_batch.visible = false
	add_child(_batch)
	_filters = UI.flow(self, T.space("sm"))
	_list = UI.vbox(self, T.space("md"))
	render()


## Polling refresh: only touch what changed. The page chrome and the grid layout are rebuilt only when
## their inputs change; individual cards are rebuilt in place (keyed by tab id) when their data changes,
## so there is no flicker or scroll jump every poll.
func on_data() -> void:
	var chrome := JSON.stringify([app.tabs.map(func(t: Dictionary) -> Array: return [UI.display_state(t), t.get("group", "")]), app.slots, app.user.get("balance"), filter, group_filter, app.server, app.content_width(), selecting, selected.size(), app.config.get("maintenance")])
	if chrome != _chrome_sig:
		_chrome_sig = chrome
		_render_chrome()
	var shown := _shown()
	var layout := JSON.stringify([shown.map(func(t: Dictionary) -> Array: return [str(t.id), str(t.get("group", ""))]), columns_for(300.0), app.tabs.is_empty(), filter, group_filter])
	if layout != _layout_sig:
		_layout_sig = layout
		_render_list(shown)
		return
	for t in shown:
		var id := str(t.id)
		var sig := _card_sig(t)
		if sig != _card_sigs.get(id, "") and _slots_by_id.has(id):
			_card_sigs[id] = sig
			var slot: Control = _slots_by_id[id]
			UI.clear(slot)
			_tab_card(slot, t)


func on_resize() -> void:
	_chrome_sig = ""
	_layout_sig = ""
	on_data()


func _card_sig(t: Dictionary) -> String:
	return JSON.stringify([t, app.tab_kind(t), _game_title(t), int(UI.now() / 60.0), selecting, selected.has(str(t.id))])


func _shown() -> Array:
	var shown: Array = []
	for t in app.tabs:
		if filter != "all" and UI.display_state(t) != filter:
			continue
		var g := str(t.get("group", ""))
		if group_filter == "__none__" and not g.is_empty():
			continue
		if not group_filter.is_empty() and group_filter != "__none__" and g != group_filter:
			continue
		shown.append(t)
	return shown


func _refresh_cards() -> void:
	_chrome_sig = ""
	on_data()


func render() -> void:
	_chrome_sig = ""
	_layout_sig = ""
	on_data()


func _render_chrome() -> void:
	var counts := {"all": app.tabs.size()}
	for t in app.tabs:
		var st := UI.display_state(t)
		counts[st] = int(counts.get(st, 0)) + 1
	var free_slots := 0
	for s in app.slots:
		if s.get("tab_id") == null and int(s.expires) > UI.now():
			free_slots += 1

	# Summary + primary action + secondary menu
	UI.clear(_bar)
	var summary := "%d tab · %d %s" % [app.tabs.size(), int(counts.get("running", 0)), T.status_label("running").to_lower()]
	if free_slots > 0:
		summary += " · %d slot trống" % free_slots
	var sl := UI.label(_bar, summary if not app.tabs.is_empty() else "", "BodyMutedLabel")
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not app.tabs.is_empty():
		UI.menu_button(_bar, "⋯" if app.compact else "Thao tác  ▾", [
			["Chọn nhiều tab", [func() -> void:
				selecting = not selecting
				selected.clear()
				_refresh_cards(), selecting]],
			null,
			["Chạy tất cả", func() -> void: Actions.batch(app, "running")],
			["Dừng tất cả", func() -> void: Actions.batch(app, "stopped")],
		], "")
	var rent := UI.button(_bar, "+ Thuê tab", func() -> void: Actions.rent(app), "PrimaryButton")
	rent.disabled = app.maintenance_on()
	if rent.disabled:
		rent.tooltip_text = "Đang bảo trì — tạm thời chưa thuê được tab."

	# Multi-select batch bar
	UI.clear(_batch)
	_batch.visible = selecting
	if selecting:
		var br := UI.flow(_batch, T.space("sm"))
		var cnt := UI.label(br, "Đã chọn %d tab" % selected.size(), "StrongLabel", false)
		cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ids := selected.keys()
		var none := ids.is_empty()
		for a in [["Chạy", "start"], ["Dừng", "stop"], ["Khởi động lại", "restart"]]:
			var action: String = a[1]
			UI.button(br, a[0], func() -> void:
				await Actions.batch_ids(app, selected.keys(), action)
				_refresh_cards(), "").disabled = none
		UI.button(br, "Nhóm…", func() -> void: Actions.group_dialog(app, {}, selected.keys()), "").disabled = none
		UI.button(br, "Chọn tất cả", func() -> void:
			for t in _shown():
				selected[str(t.id)] = true
			_refresh_cards(), "GhostButton")
		UI.button(br, "Xong", func() -> void:
			selecting = false
			selected.clear()
			_refresh_cards(), "GhostButton")

	UI.clear(_notice)
	var cheap: Dictionary = app.cheapest_plan()
	if not cheap.is_empty() and int(app.user.get("balance", 0)) < int(cheap.price):
		_notice_row("Số dư thấp hơn gói rẻ nhất (%s)." % UI.money(cheap.price), "Nạp tiền", func() -> void: app.go("wallet"), T.color("warn"))
	var svc: Array = app.server_state()
	if not app.server.is_empty() and svc[1] != T.color("success"):
		_notice_row("Dịch vụ: %s. Có thể chưa tạo hoặc bật thêm tab lúc này." % svc[0], "", Callable(), svc[1])

	UI.clear(_filters)
	_filters.visible = app.tabs.size() > 1
	for f in FILTERS:
		var n := int(counts.get(f, 0))
		if f != "all" and n == 0 and f != filter:
			continue
		var text := ("Tất cả" if f == "all" else T.status_label(f)) + "  %d" % n
		var b := UI.button(_filters, text, func() -> void:
			filter = f
			on_data(), "ChipButtonActive" if f == filter else "ChipButton")
		b.custom_minimum_size.y = UI.target_h(32)
	var groups := Actions.groups(app)
	if not groups.is_empty():
		_filters.visible = true
		var gopts: Array = [["", "Mọi nhóm"]]
		for g in groups:
			gopts.append([g, g])
		gopts.append(["__none__", "Chưa nhóm"])
		var items: Array = []
		var current := "Mọi nhóm"
		for o in gopts:
			var gid: String = o[0]
			if gid == group_filter:
				current = o[1]
			items.append([o[1], func() -> void:
				group_filter = gid
				on_data()])
		var gm := UI.menu_button(_filters, "Nhóm: %s  ▾" % current, items, "ChipButtonActive" if not group_filter.is_empty() else "ChipButton")
		gm.custom_minimum_size.y = UI.target_h(32)

func _render_list(shown: Array) -> void:
	var cheap: Dictionary = app.cheapest_plan()
	UI.clear(_list)
	_slots_by_id.clear()
	_card_sigs.clear()
	if app.tabs.is_empty():
		var hint := "Mỗi tab là một máy chơi game Java riêng, chạy 24/24. Thuê tab rồi chọn game sau cũng được."
		if not cheap.is_empty():
			hint += " Từ %s / %d ngày." % [UI.money(cheap.price), int(cheap.days)]
		UI.empty_state(_list, "Bạn chưa có tab nào", hint, "+ Thuê tab đầu tiên", func() -> void: Actions.rent(app))
		return
	if shown.is_empty():
		UI.empty_state(_list, "Không có tab phù hợp", "Không có tab nào ở trạng thái \"%s\"." % T.status_label(filter), "Xem tất cả", func() -> void:
			filter = "all"
			on_data())
		return
	# Group headers when tabs are grouped and no single group is filtered.
	var sections: Array = []
	if group_filter.is_empty() and not Actions.groups(app).is_empty():
		for g in Actions.groups(app) + [""]:
			var part := shown.filter(func(t: Dictionary) -> bool: return str(t.get("group", "")) == g)
			if not part.is_empty():
				sections.append([g, part])
	else:
		sections.append([null, shown])
	for sec in sections:
		if sec[0] != null:
			var h := UI.hbox(_list, T.space("sm"))
			UI.label(h, sec[0] if str(sec[0]) != "" else "Chưa nhóm", "SubheadingLabel", false)
			UI.badge(h, str(sec[1].size()), T.color("dim"))
		_render_grid(sec[1])


func _render_grid(shown: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = columns_for(300.0)
	grid.add_theme_constant_override("h_separation", T.space("lg"))
	grid.add_theme_constant_override("v_separation", T.space("lg"))
	_list.add_child(grid)
	for t in shown:
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(slot)
		_slots_by_id[str(t.id)] = slot
		_card_sigs[str(t.id)] = _card_sig(t)
		_tab_card(slot, t)


func _notice_row(text: String, action: String, cb: Callable, color: Color) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.1)
	sb.border_color = Color(color, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(T.radius("md"))
	sb.content_margin_left = T.space("lg")
	sb.content_margin_right = T.space("sm")
	sb.content_margin_top = T.space("sm")
	sb.content_margin_bottom = T.space("sm")
	p.add_theme_stylebox_override("panel", sb)
	_notice.add_child(p)
	var row := UI.hbox(p, T.space("md"))
	var l := UI.label(row, text, "")
	l.add_theme_color_override("font_color", color.lightened(0.2))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not action.is_empty():
		UI.button(row, action, cb, "GhostButton").custom_minimum_size.y = UI.target_h(32)


func _game_title(t: Dictionary) -> String:
	if t.get("custom_jar_id") != null:
		for j in app.jars:
			if str(j.id) == str(t.custom_jar_id):
				return str(j.filename)
	if t.get("game") == null or str(t.get("game", "")).is_empty():
		return "Chưa chọn game"
	return str(app.game(str(t.game)).get("name", t.game))


func _tab_card(parent: Node, t: Dictionary) -> void:
	var st := UI.display_state(t)
	var expired := Actions.is_expired(t)
	var live := st in ["running", "queued"]
	var c := UI.card(parent, "CardLive" if st == "running" else "Card", T.space("md"))
	var panel := c.get_parent() as PanelContainer
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Live thumbnail (click to play)
	var thumb := Button.new()
	thumb.focus_mode = Control.FOCUS_NONE
	thumb.custom_minimum_size.y = 168
	thumb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if live else Control.CURSOR_ARROW
	var sb := StyleBoxFlat.new()
	sb.bg_color = T.color("screen")
	sb.set_corner_radius_all(T.radius("md"))
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var x: StyleBoxFlat = sb.duplicate()
		if s in ["hover", "hover_pressed"] and live:
			x.border_color = Color(T.color("accent_2"), 0.7)
			x.set_border_width_all(1)
		thumb.add_theme_stylebox_override(s, x)
	c.add_child(thumb)
	var tex := TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(tex)
	if live:
		app.thumbs.subscribe(str(t.id), tex, app.tab_kind(t) == "midp")
		thumb.pressed.connect(func() -> void: app.go("viewer", {"id": str(t.id)}))
	else:
		var cover := UI.vbox(thumb, T.space("sm"))
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.alignment = BoxContainer.ALIGNMENT_CENTER
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := UI.image(cover, UI.game_icon("custom"), Vector2(40, 40))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.modulate.a = 0.55
		var msg := UI.label(cover, T.status_label(st), "MutedLabel", false)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Title row: (selection) + name + status chip
	var head := UI.hbox(c, T.space("sm"))
	if selecting:
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_pressed_no_signal(selected.has(str(t.id)))
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				selected[str(t.id)] = true
			else:
				selected.erase(str(t.id))
			_refresh_cards())
		head.add_child(cb)
	UI.label_clip(head, str(t.name), "SubheadingLabel")
	UI.status_badge(head, t)
	# Meta row: game + kind + expiry chip (the only expiry warning on the card)
	var meta := UI.hbox(c, T.space("xs"))
	UI.label_clip(meta, _game_title(t), "MutedLabel")
	var kind: String = app.tab_kind(t)
	if kind != "":
		Actions.kind_badge(meta, kind)
	var left := int(t.get("expires", 0)) - UI.now()
	var alert := int(app.uprefs().get("expiry_alert_hours", 24)) * 3600
	if expired:
		pass
	elif left < alert:
		UI.badge(meta, UI.time_left(t.expires), T.color("warn"))
	else:
		UI.badge(meta, UI.time_left(t.expires), T.color("dim"))
	if not str(t.get("restart_at", "")).is_empty() or not str(t.get("group", "")).is_empty():
		var chips := UI.flow(c, T.space("xs"))
		if not str(t.get("restart_at", "")).is_empty():
			UI.badge(chips, "⟳ %s hằng ngày" % str(t.restart_at), T.color("info")).tooltip_text = "Tự khởi động lại mỗi ngày"
		if not str(t.get("group", "")).is_empty():
			UI.badge(chips, str(t.group), T.color("dim"))
	if st == "error" and str(t.get("error", "")).strip_edges() != "":
		UI.label(c, str(t.error), "DangerLabel")

	# Actions: one primary + overflow
	var row := UI.hbox(c, T.space("sm"))
	var primary: Button
	if expired:
		primary = UI.button(row, "Gia hạn", func() -> void: Actions.renew(app, t, false), "PrimaryButton")
	elif st == "idle":
		primary = UI.button(row, "Chọn game", func() -> void: Actions.change_game(app, t), "PrimaryButton")
	elif live:
		primary = UI.button(row, "Chơi", func() -> void: app.go("viewer", {"id": str(t.id)}), "PrimaryButton")
	else:
		primary = UI.button(row, "Bật & chơi", func() -> void:
			await Actions.toggle(app, t)
			app.go("viewer", {"id": str(t.id)}), "PrimaryButton")
		primary.disabled = st == "stopping"
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.custom_minimum_size.y = UI.target_h(40)
	var items: Array = []
	if not expired:
		items.append(["Đổi game", func() -> void: Actions.change_game(app, t)])
		if st != "idle":
			items.append(["Dừng" if str(t.desired) == "running" else "Chạy", func() -> void: Actions.toggle(app, t)])
		if str(t.desired) == "running" and st != "idle":
			items.append(["Khởi động lại", func() -> void: Actions.restart(app, t)])
		if app.tab_kind(t) != "jar" and not Actions.screens(app).is_empty():
			items.append(["Màn hình (%s)…" % str(Actions.screen_info(app, str(t.get("screen", "240x320"))).label), func() -> void: Actions.pick_screen(app, t)])
		items.append(["Gia hạn…", func() -> void: Actions.renew(app, t, false)])
		if str(t.plan) != "trial":
			var on := bool(t.get("auto_renew", false))
			items.append(["Tự động gia hạn", [func() -> void: Actions.set_auto_renew(app, t, not on), on]])
	if not expired:
		items.append(["Hẹn giờ khởi động lại…", func() -> void: Actions.schedule_dialog(app, t)])
		items.append(["Chia sẻ…", func() -> void: Actions.share_dialog(app, t)])
	items.append(null)
	items.append(["Nhóm…", func() -> void: Actions.group_dialog(app, t)])
	items.append(["Đổi tên…", func() -> void: Actions.rename(app, t)])
	items.append(["Nhật ký", func() -> void: Actions.logs(app, t)])
	if Actions.can_release(t):
		items.append(null)
		items.append(["Giải phóng tab…", func() -> void: Actions.release(app, t)])
	var more := UI.menu_button(row, "⋯", items, "")
	more.custom_minimum_size = Vector2(UI.target_h(44), UI.target_h(40))
	more.tooltip_text = "Thêm thao tác"
