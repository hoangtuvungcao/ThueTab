extends VBoxContainer
## Base for all pages. Main sets `app` + `params`, then calls build().
## on_data() runs after each poll; by default it re-renders the dynamic part only when
## signature() changes, so forms and scroll position are not disturbed.

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")
const Api := preload("res://native/api.gd")

var app: Node
var params: Dictionary = {}
var _signature: String = ""
const PER_PAGE := 20
var _pages: Dictionary = {}  # list key -> current page (kept while the page re-renders)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", T.space("xl"))


func build() -> void:
	pass


## Extra data collections Main should poll while this page is open: "slots", "jars", "wallet", "admin".
func needs() -> Array:
	return []


func signature() -> Variant:
	return null


func render() -> void:
	pass


func on_data() -> void:
	var sig := JSON.stringify(signature())
	if sig == _signature:
		return
	_signature = sig
	render()


func on_resize() -> void:
	_signature = ""
	on_data()


func columns_for(min_width: float) -> int:
	return maxi(1, int(app.content_width() / min_width))


# ---------- pagination ----------

## The slice of `items` on the current page of list `key`.
func _page_of(key: String, items: Array, per: int = PER_PAGE) -> Array:
	var pages := maxi(1, ceili(items.size() / float(per)))
	var p := clampi(int(_pages.get(key, 0)), 0, pages - 1)
	_pages[key] = p
	return items.slice(p * per, (p + 1) * per)


## "‹ Trước · Trang 2/5 · 87 mục · Sau ›" under a list; hidden when it fits on one page.
func _pager(parent: Node, key: String, total: int, per: int = PER_PAGE, redraw: Callable = Callable()) -> void:
	var pages := ceili(total / float(per))
	if pages <= 1:
		return
	var p := int(_pages.get(key, 0))
	var go := func(to: int) -> void:
		_pages[key] = to
		if redraw.is_valid():
			redraw.call()
		else:
			render()
	var row := UI.hbox(parent, T.space("sm"))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.button(row, "‹ Trước", go.bind(p - 1), "GhostButton").disabled = p == 0
	UI.label(row, "Trang %d/%d · %d mục" % [p + 1, pages, total], "MutedLabel", false).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.button(row, "Sau ›", go.bind(p + 1), "GhostButton").disabled = p >= pages - 1
