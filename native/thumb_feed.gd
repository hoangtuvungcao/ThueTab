extends Node
## Shared live-thumbnail service: polls GET /tabs/{id}/frame for every subscribed tab, staggered so each
## tab refreshes about every tokens.poll_seconds.wall s, with at most one request in flight per tab.
## Used by tab cards and the multi-screen wall (no streams there by design).

const T := preload("res://native/tokens.gd")
const UI := preload("res://native/ui.gd")

var api: Node
var _rects: Dictionary = {}  # tab id -> Array[TextureRect] (weakly: invalid ones are pruned)
var _textures: Dictionary = {}  # tab id -> ImageTexture (kept between page rebuilds)
var _busy: Dictionary = {}
var _cursor: int = 0
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start(0.5)


## Show tab `id`'s latest thumbnail in `rect` and keep it updated while the rect lives.
func subscribe(id: String, rect: TextureRect, pixelated: bool = false) -> void:
	if pixelated:
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var list: Array = _rects.get(id, [])
	list.append(rect)
	_rects[id] = list
	if _textures.has(id):
		rect.texture = _textures[id]
	else:
		_fetch(id)


func clear() -> void:
	_rects.clear()
	_textures.clear()


func _prune() -> Array:
	var ids: Array = []
	for id in _rects.keys():
		var alive: Array = (_rects[id] as Array).filter(func(r: Variant) -> bool: return is_instance_valid(r) and (r as Node).is_inside_tree())
		if alive.is_empty():
			_rects.erase(id)
			_textures.erase(id)  # card left the page: free its texture
		else:
			_rects[id] = alive
			ids.append(id)
	return ids


func _tick() -> void:
	var ids := _prune()
	var n := maxi(1, ids.size())
	_timer.wait_time = maxf(0.25, float(T.poll("wall")) / n)
	if ids.is_empty() or api == null or str(api.token).is_empty():
		return
	# Only poll cards that are actually on screen (the server only renders thumbnails while requested).
	var vis := ids.filter(func(id: String) -> bool: return _rects[id].any(_on_screen))
	if vis.is_empty():
		return
	_cursor = (_cursor + 1) % vis.size()
	_fetch(vis[_cursor])


static func _on_screen(r: Variant) -> bool:
	var c := r as Control
	if c == null or not c.is_visible_in_tree():
		return false
	return c.get_viewport_rect().intersects(c.get_global_rect())


func _fetch(id: String) -> void:
	if _busy.get(id, false):
		return
	_busy[id] = true
	var r: Dictionary = await api.fetch_bytes("/tabs/%s/frame" % id, 8.0)
	_busy[id] = false
	if not r.ok:
		return
	var img := UI.decode_image(r.data)
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var tex: ImageTexture = _textures.get(id)
	if tex and Vector2i(tex.get_size()) == img.get_size() and tex.get_format() == img.get_format():
		tex.update(img)
	else:
		tex = ImageTexture.create_from_image(img)
		_textures[id] = tex
	for rect in _rects.get(id, []):
		if is_instance_valid(rect):
			rect.texture = tex
			if img.get_height() > img.get_width():
				rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
