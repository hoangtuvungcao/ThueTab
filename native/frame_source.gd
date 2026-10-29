extends Node
## Frame source for the viewer. This implementation polls GET /tabs/{id}/frame (PNG) every
## tokens.poll_seconds.frame s with one request in flight. A WebSocket source (JPEG frames +
## low-latency input) can replace it by emitting the same signals and implementing the same methods.

signal frame(image: Image)
signal waiting(text: String)  # no fresh frame yet (tab starting) — text is user-facing
signal failed(text: String)

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")

var api: Node
var tab_id: String = ""
var paused: bool = false
var _busy: bool = false
var _timer: Timer


func setup(api_node: Node, id: String) -> void:
	api = api_node
	tab_id = id


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = T.poll("frame")
	_timer.timeout.connect(poll)
	add_child(_timer)
	_timer.start()
	poll()


func poll() -> void:
	if _busy or paused or tab_id.is_empty() or not is_inside_tree():
		return
	_busy = true
	var r: Dictionary = await api.fetch_bytes("/tabs/%s/frame" % tab_id, 8.0)
	_busy = false
	if not is_inside_tree() or paused:
		return
	if r.ok:
		var img := UI.decode_image(r.data)
		if img:
			frame.emit(img)
	elif r.code == 404:
		waiting.emit("Chưa có hình mới — tab đang khởi động, vui lòng đợi vài giây.")
	else:
		failed.emit(r.error)


## Input goes through the same object so a streaming source can send it over its socket instead.
func send_key(key: String) -> Dictionary:
	return await api.request("/tabs/%s/input" % tab_id, api.POST, {"key": key}, 6.0)


func send_tap(p: Vector2i, p2: Variant = null) -> Dictionary:
	var body := {"x": p.x, "y": p.y}
	if p2 is Vector2i:
		body["x2"] = p2.x
		body["y2"] = p2.y
	return await api.request("/tabs/%s/tap" % tab_id, api.POST, body, 6.0)


func send_text(text: String) -> Dictionary:
	return await api.request("/tabs/%s/text" % tab_id, api.POST, {"text": text}, 8.0)
