extends "res://native/pages/page.gd"
## "Ví": balance, top-up (only when config.payment_ready), orders and ledger.

const Actions := preload("res://native/pages/tab_actions.gd")

var _balance: Label
var _low: Label
var _orders: VBoxContainer
var _ledger: VBoxContainer


func needs() -> Array:
	return ["wallet"]


func build() -> void:
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", T.space("md"))
	top.add_theme_constant_override("v_separation", T.space("md"))
	add_child(top)

	var bal := UI.card(top, "Card", T.space("xs"))
	bal.get_parent().custom_minimum_size.x = 260
	UI.label(bal, "Số dư ví", "MutedLabel")
	bal.get_parent().theme_type_variation = "CardAccent"
	bal.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_balance = UI.label(bal, UI.money(app.user.get("balance", 0)), "HeroLabel", false)
	_balance.add_theme_color_override("font_color", T.color("accent_2"))
	UI.label(bal, "Dùng để thuê tab, mua slot và gia hạn.", "DimLabel")
	_low = UI.label(bal, "", "")
	_low.add_theme_color_override("font_color", T.color("warn"))
	_low.add_theme_font_size_override("font_size", T.font_size("sm"))

	var topup := UI.card(top, "Card", T.space("md"))
	topup.get_parent().custom_minimum_size.x = minf(420.0, app.content_width())
	if app.config.get("payment_ready", false):
		UI.label(topup, "Nạp tiền", "SubheadingLabel")
		if app.config.get("auto_topup", false):
			UI.label(topup, "Tiền tự cộng sau 5–30 giây, không cần báo admin.", "MutedLabel")
		else:
			UI.label(topup, "Sau khi chuyển khoản, đơn được xác nhận và cộng tiền vào ví.", "MutedLabel")
		var presets_cfg: Array = app.config.get("topup_presets", [20000, 50000, 100000, 200000, 500000])
		var amount := UI.field(topup, "Số tiền (VNĐ, từ 10.000 đến 5.000.000)", "50000")
		amount.text = str(int(presets_cfg[mini(1, presets_cfg.size() - 1)])) if not presets_cfg.is_empty() else "50000"
		var presets := UI.flow(topup, T.space("xs") + 2)
		for a in presets_cfg:
			var b := UI.button(presets, UI.money(a), func() -> void: amount.text = str(a), "ChipButton")
			b.custom_minimum_size.y = UI.target_h(32)
		var coupon := {}
		Actions.coupon_box(app, topup, "topup", func() -> int: return int(amount.text.replace(".", "").replace(",", "").strip_edges()) if amount.text.strip_edges().replace(".", "").is_valid_int() else 0, Callable(), coupon)
		var create := UI.button(topup, "Tạo đơn nạp", Callable(), "PrimaryButton")
		create.pressed.connect(func() -> void:
			var value := int(amount.text.replace(".", "").replace(",", "").strip_edges())
			if value < 10000 or value > 5000000:
				app.toast("Số tiền nạp phải từ 10.000đ đến 5.000.000đ.", true)
				return
			create.disabled = true
			var data := {"amount": value}
			if not str(coupon.get("code", "")).is_empty():
				data["coupon"] = coupon.code
			var r: Dictionary = await app.api.request("/wallet/orders", Api.POST, data)
			if is_instance_valid(create):
				create.disabled = false
			if r.ok:
				show_order(app, r.data)
				app.refresh()
			else:
				app.toast(r.error, true))
	else:
		UI.label(topup, "Nạp tiền", "SubheadingLabel")
		UI.label(topup, "Nạp tiền đang tạm ngưng. Vui lòng quay lại sau.", "BodyMutedLabel")

	UI.label(self, "Đơn nạp gần đây", "SubheadingLabel")
	_orders = UI.vbox(self, T.space("sm"))
	UI.label(self, "Biến động số dư", "SubheadingLabel")
	_ledger = UI.vbox(self, 0)
	render()


func signature() -> Variant:
	return [app.wallet, app.user.get("balance")]


func render() -> void:
	_balance.text = UI.money(app.user.get("balance", 0))
	var cheap: Dictionary = app.cheapest_plan()
	var low: bool = not cheap.is_empty() and int(app.user.get("balance", 0)) < int(cheap.price)
	_low.visible = low
	if low:
		_low.text = "Số dư thấp hơn gói rẻ nhất (%s)." % UI.money(cheap.price)
	UI.clear(_orders)
	var orders: Array = app.wallet.get("orders", [])
	if orders.is_empty():
		UI.label(_orders, "Chưa có đơn nạp nào.", "MutedLabel")
	else:
		var c := UI.card(_orders, "Card", T.space("sm"))
		for i in orders.size():
			var o: Dictionary = orders[i]
			if i > 0:
				UI.separator(c)
			var row := UI.hbox(c, T.space("md"))
			var info := UI.vbox(row, 0)
			UI.label_clip(info, "%s · %s" % [UI.money(o.amount), str(o.code)], "StrongLabel")
			UI.label_clip(info, UI.datetime(o.get("created")), "DimLabel")
			var st := str(o.status)
			UI.badge(row, order_label(st), order_color(st))
			if st == "pending":
				UI.button(row, "Xem", func() -> void: show_order(app, o), "GhostButton")
	UI.clear(_ledger)
	var ledger: Array = app.wallet.get("ledger", [])
	if ledger.is_empty():
		UI.label(_ledger, "Chưa có giao dịch.", "MutedLabel")
		return
	var lc := UI.card(_ledger, "Card", T.space("sm"))
	for i in mini(ledger.size(), 50):
		var item: Dictionary = ledger[i]
		if i > 0:
			UI.separator(lc)
		var row := UI.hbox(lc, T.space("md"))
		var info := UI.vbox(row, 0)
		UI.label_clip(info, str(item.description), "")
		UI.label_clip(info, UI.datetime(item.get("created")), "DimLabel")
		var amt := int(item.amount)
		var v := UI.label(row, ("+" if amt > 0 else "") + UI.money(amt), "StrongLabel", false)
		v.add_theme_color_override("font_color", T.color("success") if amt > 0 else T.color("ink"))


static func order_label(st: String) -> String:
	return T.order_label(st)


static func order_color(st: String) -> Color:
	return T.order_color(st)


## Payment instructions for one order. Polls the wallet until the order is paid.
static func show_order(app: Node, order: Dictionary) -> void:
	var body: VBoxContainer = app.open_modal("Nạp %s" % UI.money(order.amount), 480)
	var status := UI.hbox(body, T.space("sm"))
	UI.badge(status, T.order_label("pending"), T.order_color("pending"))
	UI.label(status, "Đang chờ xác nhận…", "MutedLabel")

	if str(order.get("qr_url", "")) != "":
		var qr_wrap := CenterContainer.new()
		body.add_child(qr_wrap)
		var qr_panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.set_corner_radius_all(T.radius("md"))
		sb.set_content_margin_all(T.space("sm"))
		qr_panel.add_theme_stylebox_override("panel", sb)
		qr_wrap.add_child(qr_panel)
		var qr := UI.image(qr_panel, null, Vector2(220, 220))
		var loading := UI.label(body, "Đang tải mã QR…", "DimLabel")
		loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_qr(app, str(order.qr_url), qr, loading)

	var info := UI.card(body, "CardInset", T.space("sm"))
	_info_row(app, info, "Ngân hàng", str(order.get("bank", "")), false)
	_info_row(app, info, "Số tài khoản", str(order.get("account", "")), true)
	_info_row(app, info, "Chủ tài khoản", str(order.get("account_name", "")), false)
	_info_row(app, info, "Số tiền", UI.money(order.amount), false)
	_info_row(app, info, "Nội dung", str(order.code), true)
	if app.config.get("auto_topup", false):
		UI.label(body, "Chuyển khoản đúng số tiền và nội dung. Tiền tự cộng sau 5–30 giây, không cần báo admin.", "MutedLabel")
	else:
		UI.label(body, "Chuyển khoản đúng số tiền và nội dung; đơn sẽ được xác nhận và cộng tiền vào ví.", "MutedLabel")
	var cancel := UI.button(body, "Hủy đơn này", Callable(), "GhostButton")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.pressed.connect(func() -> void:
		var r: Dictionary = await app.api.request("/wallet/orders/%s" % str(order.id), Api.DELETE)
		if r.ok:
			app.toast("Đã hủy đơn %s." % str(order.code))
			app.close_modal()
			app.refresh(true)
		else:
			app.toast(r.error, true))

	var timer := Timer.new()
	timer.wait_time = T.poll("data")
	body.add_child(timer)
	timer.timeout.connect(func() -> void:
		var r: Dictionary = await app.api.request("/wallet")
		if not r.ok or not is_instance_valid(body) or not body.is_inside_tree():
			return
		app.wallet = r.data
		for o in r.data.get("orders", []):
			if str(o.id) == str(order.id) and str(o.status) == "cancelled":
				timer.stop()
				app.close_modal()
			if str(o.id) == str(order.id) and str(o.status) == "paid":
				timer.stop()
				app.close_modal()
				app.toast("Đã nhận %s. Cảm ơn bạn!" % UI.money(order.amount))
				app.refresh(true))
	timer.start()


static func _info_row(app: Node, parent: Node, key: String, value: String, copy: bool) -> void:
	if value.is_empty():
		return
	var row := UI.hbox(parent, T.space("sm"))
	var k := UI.label(row, key, "MutedLabel", false)
	k.custom_minimum_size.x = 110
	var v := UI.label(row, value, "StrongLabel")
	v.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	if copy:
		var b := UI.button(row, "Sao chép", func() -> void:
			DisplayServer.clipboard_set(value)
			app.toast("Đã sao chép: " + value), "GhostButton")
		b.custom_minimum_size.y = UI.target_h(30)


static func _load_qr(app: Node, url: String, target: TextureRect, loading: Label) -> void:
	var r: Dictionary = await app.api.fetch_bytes(url, 15.0, false)
	if not is_instance_valid(target):
		return
	var img: Image = UI.decode_image(r.data) if r.ok else null
	if img:
		target.texture = ImageTexture.create_from_image(img)
		loading.visible = false
	else:
		loading.text = "Không tải được mã QR. Hãy chuyển khoản theo thông tin bên dưới."
