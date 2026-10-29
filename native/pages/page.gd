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
