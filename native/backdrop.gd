extends Control
## App background: deep bg color, faint grid (tokens.effects.grid_pattern) and two soft gradient glows.

const T := preload("res://native/tokens.gd")
const GRID := 40.0

var _glow_a: GradientTexture2D
var _glow_b: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := T.gradient()
	_glow_a = _radial(Color(g[0], 0.16))
	_glow_b = _radial(Color(g[1], 0.08))
	resized.connect(queue_redraw)


static func _radial(c: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, c)
	grad.set_color(1, Color(c, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), T.color("bg"))
	var big := maxf(size.x, size.y)
	draw_texture_rect(_glow_a, Rect2(Vector2(size.x - big * 0.55, -big * 0.45), Vector2(big, big) * 0.9), false)
	draw_texture_rect(_glow_b, Rect2(Vector2(-big * 0.35, size.y - big * 0.45), Vector2(big, big) * 0.8), false)
	if T.effect("grid_pattern", false):
		var line := Color(T.color("border"), 0.22)
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
			x += GRID
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
			y += GRID
