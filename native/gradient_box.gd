extends StyleBox
## Rounded rectangle filled with a horizontal two-color gradient plus an optional soft outer glow.
## Used for the primary button (tokens.effects.gradient) — StyleBoxFlat cannot do gradients.

@export var color_from: Color = Color("#38bdf8")
@export var color_to: Color = Color("#34d399")
@export var radius: float = 12.0
@export var glow_color: Color = Color(0, 0, 0, 0)
@export var glow_size: float = 0.0
@export var brightness: float = 1.0

const CORNER_STEPS := 6


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect


func _rounded_points(rect: Rect2, r: float) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI / 2.0],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI / 2.0],
		[rect.position + Vector2(r, r), PI],
	]
	for c in corners:
		for i in CORNER_STEPS + 1:
			var a: float = c[1] + (PI / 2.0) * float(i) / CORNER_STEPS
			pts.append(c[0] + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if glow_size > 0.0 and glow_color.a > 0.0:
		var layers := 5
		for i in layers:
			var grow := glow_size * float(layers - i) / layers
			var c := glow_color
			c.a = glow_color.a * (0.12 + 0.18 * float(i) / layers)
			var pts := _rounded_points(rect.grow(grow), radius + grow)
			RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([c]))
	var points := _rounded_points(rect, radius)
	var colors := PackedColorArray()
	for p in points:
		var t := clampf((p.x - rect.position.x) / maxf(1.0, rect.size.x), 0.0, 1.0)
		var col := color_from.lerp(color_to, t)
		col = Color(col.r * brightness, col.g * brightness, col.b * brightness, col.a)
		colors.append(col)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)
