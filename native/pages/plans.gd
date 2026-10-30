extends "res://native/pages/page.gd"
## "Bảng giá": plans from config, buy empty slots, owned slots with renew.

const Actions := preload("res://native/pages/tab_actions.gd")

var _grid: GridContainer
var _slots: VBoxContainer


func needs() -> Array:
	return ["slots"]


func build() -> void:
	var c: Dictionary = app.config
	UI.label(self, "Mỗi tab là một máy chơi game riêng chạy 24/24. Tối đa %d tab mỗi tài khoản." % int(c.get("max_tabs", 20)), "BodyMutedLabel")
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", T.space("md"))
	_grid.add_theme_constant_override("v_separation", T.space("md"))
	add_child(_grid)
	_build_plans()
	_build_buy()
	UI.label(self, "Slot của bạn", "SubheadingLabel")
	_slots = UI.vbox(self, T.space("sm"))
	render()


func on_resize() -> void:
	_build_plans()
	super.on_resize()


func _build_plans() -> void:
	UI.clear(_grid)
	var plans: Array = app.config.get("plans", [])
	_grid.columns = clampi(columns_for(200.0), 1, maxi(1, plans.size()))
	var best: Dictionary = app.best_value_plan()
	for p in plans:
		var card := UI.card(_grid, "Card", T.space("xs"))
		card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
		var head := UI.hbox(card, T.space("sm"))
		UI.label(head, str(p.name), "StrongLabel")
		if p == best and plans.size() > 1:
			UI.badge(head, "Tiết kiệm nhất", T.color("accent"))
		UI.label(card, UI.money(p.price), "HeadingLabel")
		UI.label(card, "%d ngày · ≈ %s/ngày" % [int(p.days), UI.money(roundi(float(p.price) / maxf(1.0, float(p.days))))], "MutedLabel")


func _build_buy() -> void:
	var c := UI.card(self, "Card", T.space("md"))
	UI.label(c, "Mua slot trống", "SubheadingLabel")
	UI.label(c, "Slot là chỗ chạy đã trả tiền — gắn tab vào slot bất cứ lúc nào mà không trả thêm.", "BodyMutedLabel")
	var row := UI.flow(c, T.space("md"))
	var qbox := UI.vbox(row, T.space("xs") + 2)
	qbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.label(qbox, "Số lượng", "MutedLabel")
	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = 20
	qty.value = 1
	qty.custom_minimum_size = Vector2(120, 40)
	qbox.add_child(qty)
	var pwrap := UI.vbox(row, 0)
	pwrap.custom_minimum_size.x = 260
	var plan_opt := UI.option(pwrap, "Gói")
	var plans: Array = app.config.get("plans", [])
	for p in plans:
		plan_opt.add_item("%s · %d ngày · %s" % [str(p.name), int(p.days), UI.money(p.price)])
	plan_opt.selected = 0 if not plans.is_empty() else -1
	var coupon_slot := UI.vbox(c, 0)
	var total := UI.label(c, "", "StrongLabel")
	var buy := UI.button(c, "Mua slot", Callable(), "PrimaryButton")
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var coupon := {}
	var update := func() -> void:
		if plan_opt.selected < 0:
			return
		var sum := int(plans[plan_opt.selected].price) * int(qty.value)
		if not str(coupon.get("code", "")).is_empty():
			sum = maxi(0, sum - int(coupon.get("discount", 0)))
		total.text = "Tổng: %s  (số dư %s)" % [UI.money(sum), UI.money(app.user.get("balance", 0))]
		buy.disabled = sum > int(app.user.get("balance", 0)) or app.maintenance_on()
		if app.maintenance_on():
			buy.tooltip_text = "Đang bảo trì — tạm thời chưa mua được slot."
	Actions.coupon_box(app, coupon_slot, "rent", func() -> int: return int(plans[maxi(plan_opt.selected, 0)].price) * int(qty.value) if not plans.is_empty() else 0, update, coupon)
	qty.value_changed.connect(func(_v: float) -> void:
		if not str(coupon.get("code", "")).is_empty():
			coupon.recheck.call()
		update.call())
	plan_opt.item_selected.connect(func(_i: int) -> void:
		if not str(coupon.get("code", "")).is_empty():
			coupon.recheck.call()
		update.call())
	update.call()
	UI.on_press(buy, func() -> void:
		buy.disabled = true
		var data := {"quantity": int(qty.value), "plan": str(plans[plan_opt.selected].id)}
		if not str(coupon.get("code", "")).is_empty():
			data["coupon"] = coupon.code
		await app.act("/slots", Api.POST, data, "Đã mua %d slot." % int(qty.value))
		if is_instance_valid(buy):
			update.call())


func signature() -> Variant:
	return [app.slots, int(UI.now() / 60.0)]


func render() -> void:
	UI.clear(_slots)
	if app.slots.is_empty():
		UI.label(_slots, "Bạn chưa có slot nào. Thuê tab hoặc mua slot để bắt đầu.", "MutedLabel")
		return
	var c := UI.card(_slots, "Card", T.space("sm"))
	for i in app.slots.size():
		var s: Dictionary = app.slots[i]
		if i > 0:
			UI.separator(c)
		var row := UI.hbox(c, T.space("md"))
		var info := UI.vbox(row, 0)
		var used := s.get("tab_name") != null
		UI.label_clip(info, "Slot #%s · %s" % [str(s.id).left(6), str(app.plan(str(s.plan)).name)], "StrongLabel")
		UI.label_clip(info, "%s · hết hạn %s" % [UI.time_left(s.expires), UI.datetime(s.expires)], "DimLabel")
		if int(s.expires) <= UI.now():
			UI.badge(row, T.status_label("expired"), T.status_color("expired"))
		elif used:
			UI.badge(row, str(s.tab_name), T.color("info"))
		else:
			UI.badge(row, "Trống", T.color("success"))
		UI.button(row, "Gia hạn", func() -> void: Actions.renew(app, s, true), "GhostButton")
