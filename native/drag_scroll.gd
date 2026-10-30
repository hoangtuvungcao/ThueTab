extends Node
## Touch drag-to-scroll for every ScrollContainer, also when the finger lands on a button or card (Godot gives
## the touch to that control, so the list underneath never moved). A vertical drag past SLOP scrolls the
## topmost ScrollContainer under the finger, with a short fling on release, and cancels the button press so
## the row is not opened by the swipe. Controls in the "no_drag_scroll" group (game screen, keypads) keep
## their own drags.

const SLOP := 12.0
const FRICTION := 0.02  # fling speed left after one second

var _id := -1
var _start := Vector2.ZERO
var _scroll: ScrollContainer
var _pos := 0.0
var _dragging := false
var _velocity := 0.0
var _injecting := false


func _ready() -> void:
	set_process(false)


func _input(event: InputEvent) -> void:
	if _injecting:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _id == -1:
			_id = t.index
			_start = t.position
			_dragging = false
			_stop_fling()
			_scroll = _scroll_at(t.position)
		elif not t.pressed and t.index == _id:
			_id = -1
			if _dragging:
				_dragging = false
				if absf(_velocity) > 200.0 and is_instance_valid(_scroll):
					set_process(true)
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _id or not is_instance_valid(_scroll):
			return
		if not _dragging:
			var moved := d.position - _start
			if moved.length() < SLOP:
				return
			if absf(moved.y) < absf(moved.x):
				_scroll = null  # sideways: sliders and swipes keep it
				return
			_dragging = true
			_pos = _scroll.scroll_vertical
			_cancel_press.call_deferred()  # not from inside this event's dispatch
		_pos = clampf(_pos - d.relative.y, 0.0, _max_scroll(_scroll))
		_scroll.scroll_vertical = int(_pos)
		_velocity = -d.velocity.y
		get_viewport().set_input_as_handled()
		return
	# The mouse events Godot emulates from the same touch would move the press again.
	if _dragging and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_instance_valid(_scroll) or absf(_velocity) < 20.0:
		_stop_fling()
		return
	_pos = clampf(_pos + _velocity * delta, 0.0, _max_scroll(_scroll))
	_scroll.scroll_vertical = int(_pos)
	_velocity *= pow(FRICTION, delta)
	if _pos <= 0.0 or _pos >= _max_scroll(_scroll):
		_stop_fling()


func _stop_fling() -> void:
	_velocity = 0.0
	set_process(false)


## The pressed button sees the pointer leave it, so lifting the finger does not click it.
func _cancel_press() -> void:
	var m := InputEventMouseMotion.new()
	m.position = Vector2(-100000, -100000)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	_injecting = true
	get_viewport().push_input(m)
	_injecting = false


static func _max_scroll(s: ScrollContainer) -> float:
	var bar := s.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


## Topmost ScrollContainer (last in tree order) under `p` that can scroll, or null when a "no_drag_scroll"
## control is on top there.
func _scroll_at(p: Vector2) -> ScrollContainer:
	var hit: Array = [null]
	_walk(get_tree().root, p, hit)
	var top: Variant = hit[0]
	if top is ScrollContainer and _max_scroll(top) > 1.0:
		return top
	return null


func _walk(n: Node, p: Vector2, hit: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c := n as Control
		if (c is ScrollContainer or c.is_in_group("no_drag_scroll")) and c.get_global_rect().has_point(p):
			hit[0] = c
	for child in n.get_children():
		_walk(child, p, hit)
