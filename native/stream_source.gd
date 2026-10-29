extends Node
## Real-time frame source: WebSocket ws(s)://<host>/api/tabs/{id}/stream?fps=N (design/README.md).
## Binary packets are H.264 access units when the native decoder (native/h264, class H264Decoder) is present —
## ~10x less data than JPEG, so 30/60 fps fits a slow server uplink — otherwise JPEG frames, of which only the
## newest per _process is decoded. Input (key/text/tap)
## goes over the socket as JSON, falling back to HTTP when the socket is not open. Reconnects with backoff;
## while not streaming, an embedded FrameSource polls GET /frame so a still image is shown.
## Exposes the same signals/methods as frame_source.gd, so the viewer can use either.

signal frame(image: Image)
signal waiting(text: String)
signal failed(text: String)
signal hello(info: Dictionary)
signal stats(fps: float, ping_ms: int, live: bool)

const FrameSource := preload("res://native/frame_source.gd")
const CLOSE_TEXT := {
	4401: "Phiên đăng nhập không hợp lệ. Hãy đăng nhập lại.",
	4403: "Kết nối bị từ chối.",
	4404: "Không tìm thấy tab.",
	4409: "Tab không chạy (đã dừng hoặc hết hạn).",
	4429: "Có quá nhiều người đang xem tab này. Thử lại sau.",
}

var api: Node
var tab_id: String = ""
var fps: int = 30
var paused: bool = false:
	set(v):
		paused = v
		if _poller:
			_poller.paused = v or _live
		if v:
			_close()

var _ws: WebSocketPeer
var _live: bool = false  # socket open (frames may still be pending)
var _retry_at: float = 0.0
var _backoff: float = 1.0
var _poller: Node
var _img := Image.new()
var _frames: int = 0
var _fps_t0: float = 0.0
var _fps_now: float = 0.0
var _ping_ms: int = -1
var _ping_sent: float = -1.0
var _next_ping: float = 0.0
var _dec: Object  # H264Decoder for the current connection, or null (JPEG)
var _video_errors: int = 0
var _video_off: bool = false  # decoder missing or failing: JPEG for the rest of this viewer's life
const PING_EVERY := 3.0
const ACK := "{\"type\":\"ack\"}"


func setup(api_node: Node, id: String, start_fps: int) -> void:
	api = api_node
	tab_id = id
	fps = start_fps


func _ready() -> void:
	_poller = FrameSource.new()
	_poller.setup(api, tab_id)
	_poller.frame.connect(func(img: Image) -> void:
		if not _live:
			frame.emit(img))
	_poller.waiting.connect(func(t: String) -> void: waiting.emit(t))
	_poller.failed.connect(func(t: String) -> void: failed.emit(t))
	add_child(_poller)
	_poller.paused = paused
	_fps_t0 = _now()


func _exit_tree() -> void:
	_close()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _url() -> String:
	var base: String = api.endpoint
	base = base.replace("https://", "wss://").replace("http://", "ws://")
	return "%s/api/tabs/%s/stream?fps=%d&ack=1%s" % [base, tab_id, fps, "&codec=h264" if _dec else ""]


func _connect_ws() -> void:
	# Fresh decoder per connection: the server starts every viewer at a keyframe.
	_dec = ClassDB.instantiate("H264Decoder") if not _video_off and ClassDB.class_exists("H264Decoder") else null
	_video_errors = 0
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + str(api.token)])
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 64
	var err := _ws.connect_to_url(_url())
	if err != OK:
		_ws = null
		_schedule_retry("Không mở được kết nối trực tiếp.")


func _close() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_set_live(false)


func _set_live(v: bool) -> void:
	_live = v
	if _poller:
		_poller.paused = paused or v


func _schedule_retry(text: String) -> void:
	_set_live(false)
	_retry_at = _now() + _backoff
	_backoff = minf(_backoff * 2.0, 15.0)
	if not text.is_empty():
		waiting.emit(text)


func _process(_delta: float) -> void:
	if paused or tab_id.is_empty():
		return
	var t := _now()
	if _ws == null:
		if t >= _retry_at:
			_connect_ws()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _live:
				_set_live(true)
				_backoff = 1.0
			_drain()
			# Latency: {"type":"ping","t":ms} → server echoes {"type":"pong","t":ms}.
			if t >= _next_ping:
				_next_ping = t + PING_EVERY
				_ws.send_text(JSON.stringify({"type": "ping", "t": Time.get_ticks_msec()}))
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			_ws = null
			var text: String = CLOSE_TEXT.get(code, "Mất kết nối trực tiếp — đang kết nối lại…")
			if code in [4401, 4403, 4404]:
				_set_live(false)
				_retry_at = t + 30.0
				failed.emit(text)
			else:
				_schedule_retry(text)
	if t - _fps_t0 >= 1.0:
		_fps_now = _frames / (t - _fps_t0)
		_frames = 0
		_fps_t0 = t
		stats.emit(_fps_now, _ping_ms, _live)


## Drain all queued packets. Video frames depend on the previous ones, so every one is decoded (≈1–2 ms
## each) and only the last picture is shown; for JPEG only the newest frame is decoded.
func _drain() -> void:
	var newest := PackedByteArray()
	var picture := false
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_on_text(pkt.get_string_from_utf8())
			continue
		_frames += 1
		# Acknowledge each frame: the server keeps only a few in flight, so a slow link never
		# builds up seconds of delay (inputs and FPS changes would queue behind them).
		_ws.send_text(ACK)
		if pkt.size() > 1 and pkt[0] == 0xFF and pkt[1] == 0xD8:
			newest = pkt
		elif _dec:
			var r: int = _dec.decode(pkt)
			if r == 1:
				picture = true
				_video_errors = 0
			elif r < 0:
				_video_errors += 1
	if picture:
		var w: int = _dec.get_width()
		var h: int = _dec.get_height()
		if _img.get_width() == w and _img.get_height() == h and _img.get_format() == Image.FORMAT_RGBA8:
			_img.set_data(w, h, false, Image.FORMAT_RGBA8, _dec.get_rgba())
		else:
			_img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _dec.get_rgba())
		frame.emit(_img)
	elif not newest.is_empty() and _img.load_jpg_from_buffer(newest) == OK:
		frame.emit(_img)
	if _video_errors > 30:
		# Undecodable video: reconnect asking for JPEG.
		_video_off = true
		_close()
		_retry_at = 0.0


func _on_text(raw: String) -> void:
	var m: Variant = JSON.parse_string(raw)
	if not (m is Dictionary):
		return
	match str(m.get("type", "")):
		"hello":
			if m.has("fps"):
				fps = int(m.fps)
			hello.emit(m)
		"pong":
			if m.has("t"):
				_ping_ms = maxi(0, Time.get_ticks_msec() - int(m.t))
		"error":
			failed.emit(str(m.get("detail", "Thao tác không hợp lệ.")))


func is_live() -> bool:
	return _live


func set_fps(value: int) -> void:
	fps = value
	if _live:
		_ws.send_text(JSON.stringify({"type": "fps", "fps": value}))


func _send_json(msg: Dictionary) -> bool:
	if _live and _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return _ws.send_text(JSON.stringify(msg)) == OK
	return false


func send_key(key: String) -> Dictionary:
	if _send_json({"type": "key", "key": key}):
		return {"ok": true, "error": ""}
	return await _poller.send_key(key)


func send_tap(p: Vector2i, p2: Variant = null) -> Dictionary:
	var msg := {"type": "tap", "x": p.x, "y": p.y}
	if p2 is Vector2i:
		msg["x2"] = p2.x
		msg["y2"] = p2.y
	if _send_json(msg):
		return {"ok": true, "error": ""}
	return await _poller.send_tap(p, p2)


func send_text(text: String) -> Dictionary:
	if _send_json({"type": "text", "text": text}):
		return {"ok": true, "error": ""}
	return await _poller.send_text(text)
