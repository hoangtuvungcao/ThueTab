extends Control
## Minimal stroke icons matching the lucide names used in tokens.nav (drawn, so no icon font is needed).

var icon: String = "layout-grid":
	set(v):
		icon = v
		queue_redraw()
var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _p(x: float, y: float) -> Vector2:
	# Icons are designed on a 24×24 grid like lucide.
	var s := minf(size.x, size.y) / 24.0
	var off := (size - Vector2(24, 24) * s) / 2.0
	return off + Vector2(x, y) * s


func _w() -> float:
	return maxf(1.5, minf(size.x, size.y) / 12.0)


func _poly(points: Array, closed: bool = false) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(_p(p[0], p[1]))
	if closed:
		pts.append(pts[0])
	draw_polyline(pts, color, _w(), true)


func _rect(x: float, y: float, w: float, h: float) -> void:
	_poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]], true)


func _circle(cx: float, cy: float, r: float) -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_arc(_p(cx, cy), r * s, 0, TAU, 32, color, _w(), true)


func _arc(cx: float, cy: float, r: float, from_deg: float, to_deg: float) -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_arc(_p(cx, cy), r * s, deg_to_rad(from_deg), deg_to_rad(to_deg), 24, color, _w(), true)


func _draw() -> void:
	match icon:
		"sun":
			_circle(12, 12, 4)
			for i in 8:
				var d := Vector2.from_angle(i * TAU / 8.0)
				_poly([[12 + d.x * 7, 12 + d.y * 7], [12 + d.x * 9.5, 12 + d.y * 9.5]])
		"moon":  # lucide "moon": outer arc from the top round to the right, inner arc back
			_arc(12, 12, 9, -90, -360)
			_arc(16.5, 7.5, 6.36, -135, -315)
		"layout-grid":
			_rect(3, 3, 7, 7)
			_rect(14, 3, 7, 7)
			_rect(3, 14, 7, 7)
			_rect(14, 14, 7, 7)
		"file-code":
			_poly([[14, 2], [6, 2], [4, 4], [4, 20], [6, 22], [18, 22], [20, 20], [20, 8], [14, 2]])
			_poly([[14, 2], [14, 8], [20, 8]])
			_poly([[10, 12], [8, 14.5], [10, 17]])
			_poly([[14, 12], [16, 14.5], [14, 17]])
		"wallet":
			_poly([[19, 7], [19, 4], [5, 4], [3, 6], [5, 8], [21, 8], [21, 20], [5, 20], [3, 18], [3, 6]])
			_poly([[21, 12], [17, 12], [17, 16], [21, 16]])
		"tag":
			_poly([[12, 2], [2, 2], [2, 12], [11, 21], [21, 11]], true)
			_circle(7.5, 7.5, 1.2)
		"life-buoy":
			_circle(12, 12, 10)
			_circle(12, 12, 4)
			_poly([[4.9, 4.9], [9.2, 9.2]])
			_poly([[14.8, 14.8], [19.1, 19.1]])
			_poly([[14.8, 9.2], [19.1, 4.9]])
			_poly([[4.9, 19.1], [9.2, 14.8]])
		"shield":
			_poly([[12, 22], [5, 18], [4, 12], [4, 5], [12, 2], [20, 5], [20, 12], [19, 18]], true)
		"log-out":
			_poly([[9, 21], [5, 21], [3, 19], [3, 5], [5, 3], [9, 3]])
			_poly([[16, 17], [21, 12], [16, 7]])
			_poly([[21, 12], [9, 12]])
		"arrow-left":
			_poly([[19, 12], [5, 12]])
			_poly([[12, 19], [5, 12], [12, 5]])
		"monitor-play":
			_rect(2, 3, 20, 14)
			_poly([[8, 21], [16, 21]])
			_poly([[12, 17], [12, 21]])
			_poly([[10, 7], [15, 10], [10, 13]], true)
		"user":
			_circle(12, 8, 4)
			_poly([[4, 21], [5, 17], [8, 14.5], [16, 14.5], [19, 17], [20, 21]])
		"more":
			_circle(5, 12, 1.2)
			_circle(12, 12, 1.2)
			_circle(19, 12, 1.2)
		"bell":
			_poly([[6, 16], [6, 10], [8, 6], [12, 4], [16, 6], [18, 10], [18, 16], [20, 18], [4, 18], [6, 16]])
			_poly([[10, 21], [14, 21]])
		"settings":
			_circle(12, 12, 3)
			_circle(12, 12, 8)
		"inbox":
			_poly([[3, 13], [8, 13], [10, 16], [14, 16], [16, 13], [21, 13]])
			_poly([[3, 13], [6, 5], [18, 5], [21, 13], [21, 19], [3, 19]], true)
		"x":
			_poly([[6, 6], [18, 18]])
			_poly([[18, 6], [6, 18]])
		"more-h":
			_circle(5, 12, 1.4)
			_circle(12, 12, 1.4)
			_circle(19, 12, 1.4)
		"check-circle":
			_circle(12, 12, 9)
			_poly([[8, 12.5], [11, 15], [16, 9]])
		"info":
			_circle(12, 12, 9)
			_poly([[12, 11], [12, 16]])
			_circle(12, 8, 0.6)
		"alert":
			_poly([[12, 3], [22, 20], [2, 20]], true)
			_poly([[12, 9], [12, 14]])
			_circle(12, 17, 0.6)
		"chevron-down":
			_poly([[6, 9], [12, 15], [18, 9]])
		"gamepad":
			_poly([[6, 8], [18, 8], [21, 12], [21, 16], [18, 18], [15, 15], [9, 15], [6, 18], [3, 16], [3, 12]], true)
			_poly([[7, 11], [7, 13]])
			_poly([[6, 12], [8, 12]])
			_circle(16, 11.5, 0.8)
			_circle(14.5, 13, 0.8)
		"refresh":
			draw_arc(_p(12, 12), 7.5 * minf(size.x, size.y) / 24.0, -PI * 0.15, PI * 1.55, 24, color, _w(), true)
			_poly([[19, 4.5], [19.2, 9.5], [14.5, 8.8]])
		"play":
			_poly([[8, 5], [19, 12], [8, 19]], true)
		"stop":
			_rect(7, 7, 10, 10)
		"trash":
			_poly([[4, 7], [20, 7]])
			_poly([[9, 7], [9, 4], [15, 4], [15, 7]])
			_poly([[6, 7], [7, 20], [17, 20], [18, 7]])
			_poly([[10, 11], [10, 16]])
			_poly([[14, 11], [14, 16]])
		"lock":
			_rect(5, 11, 14, 10)
			_poly([[8, 11], [8, 7], [10, 4.5], [14, 4.5], [16, 7], [16, 11]])
		"unlock":
			_rect(5, 11, 14, 10)
			_poly([[8, 11], [8, 7], [10, 4.5], [14, 4.5], [16, 6.5]])
		"clock":
			_circle(12, 12, 9)
			_poly([[12, 7], [12, 12], [15.5, 14]])
		"share":
			_circle(18, 5.5, 2.5)
			_circle(6, 12, 2.5)
			_circle(18, 18.5, 2.5)
			_poly([[8.2, 10.8], [15.8, 6.7]])
			_poly([[8.2, 13.2], [15.8, 17.3]])
		"folder":
			_poly([[3, 6], [9, 6], [11, 8], [21, 8], [21, 19], [3, 19]], true)
		"edit":
			_poly([[4, 20], [5, 15], [16, 4], [20, 8], [9, 19]], true)
			_poly([[14, 6], [18, 10]])
		"keyboard":
			_rect(2, 6, 20, 12)
			_poly([[6, 10], [7, 10]])
			_poly([[11, 10], [12, 10]])
			_poly([[16, 10], [17, 10]])
			_poly([[7, 14], [17, 14]])
		"maximize":
			_poly([[4, 9], [4, 4], [9, 4]])
			_poly([[15, 4], [20, 4], [20, 9]])
			_poly([[20, 15], [20, 20], [15, 20]])
			_poly([[9, 20], [4, 20], [4, 15]])
		"check":
			_poly([[5, 12.5], [10, 17], [19, 7]])
		"dot":
			_circle(12, 12, 1.5)
		"plus":
			_poly([[12, 5], [12, 19]])
			_poly([[5, 12], [19, 12]])
		_:
			_circle(12, 12, 9)
