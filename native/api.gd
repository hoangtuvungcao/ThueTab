extends Node
## Non-blocking HTTP client for the ThuêTab API. Every call is awaited and returns
## {ok: bool, code: int, data: Variant, error: String}. Errors use the backend's Vietnamese {detail}.

signal unauthorized
signal connectivity(online: bool)  # false after a network failure, true again on the next success

const NETWORK_ERROR := "Không kết nối được. Kiểm tra mạng rồi thử lại."

const GET := HTTPClient.METHOD_GET
const POST := HTTPClient.METHOD_POST
const PATCH := HTTPClient.METHOD_PATCH
const PUT := HTTPClient.METHOD_PUT
const DELETE := HTTPClient.METHOD_DELETE

var endpoint: String = ""  # from res://native/client.json (or --api=... for QA); never shown in the UI
var online: bool = true
var token: String = ""


func url(path: String) -> String:
	if path.begins_with("http://") or path.begins_with("https://"):
		return path
	return endpoint + "/api" + path


func _headers(extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var h := PackedStringArray(["Accept: application/json", "User-Agent: " + user_agent()])
	if not token.is_empty():
		h.append("Authorization: Bearer " + token)
	h.append_array(extra)
	return h


## JSON request. `data` = null sends no body.
func request(path: String, method: int = GET, data: Variant = null, timeout: float = 15.0) -> Dictionary:
	var headers := _headers(PackedStringArray(["Content-Type: application/json"]))
	var body := "" if data == null else JSON.stringify(data)
	return await _send(path, method, headers, body.to_utf8_buffer(), timeout, true)


## Raw binary upload (e.g. JAR files).
func request_raw(path: String, method: int, body: PackedByteArray, extra_headers: PackedStringArray, timeout: float = 120.0) -> Dictionary:
	return await _send(path, method, _headers(extra_headers), body, timeout, true)


## Fetch raw bytes (frames, QR images). `data` holds the PackedByteArray when ok.
func fetch_bytes(path: String, timeout: float = 8.0, authorized: bool = true) -> Dictionary:
	var headers := _headers() if authorized else PackedStringArray()
	return await _send(path, GET, headers, PackedByteArray(), timeout, false)


func _send(path: String, method: int, headers: PackedStringArray, body: PackedByteArray, timeout: float, parse_json: bool) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.accept_gzip = true
	add_child(http)
	var err: int
	if body.is_empty() and method == GET:
		err = http.request(url(path), headers, method)
	else:
		err = http.request_raw(url(path), headers, method, body)
	if err != OK:
		http.queue_free()
		_set_online(false)
		return _fail(0, NETWORK_ERROR)
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var bytes: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		if not path.begins_with("http"):
			_set_online(false)
		return _fail(0, NETWORK_ERROR)
	if not path.begins_with("http"):
		_set_online(true)
	var ok := code >= 200 and code < 300
	if code == 401 and not token.is_empty() and not path.begins_with("/auth/"):
		unauthorized.emit()
	if ok and not parse_json:
		return {"ok": true, "code": code, "data": bytes, "error": ""}
	var parsed: Variant = null
	var text := bytes.get_string_from_utf8()
	if not text.is_empty():
		parsed = JSON.parse_string(text)
	if ok:
		if parsed == null and not text.is_empty():
			return _fail(code, "Máy chủ trả dữ liệu không hợp lệ.")
		return {"ok": true, "code": code, "data": parsed, "error": ""}
	return _fail(code, _detail(parsed, code))


func _detail(parsed: Variant, code: int) -> String:
	if parsed is Dictionary and parsed.has("detail"):
		var d: Variant = parsed.detail
		if d is String:
			return d
		if d is Array and not d.is_empty() and d[0] is Dictionary:
			# FastAPI validation error list
			return "Dữ liệu không hợp lệ: %s" % str(d[0].get("msg", ""))
		return str(d)
	match code:
		401: return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
		403: return "Bạn không có quyền thực hiện thao tác này."
		404: return "Không tìm thấy dữ liệu."
		429: return "Thao tác quá nhanh, hãy thử lại sau ít phút."
	if code >= 500:
		return "Dịch vụ đang bận. Vui lòng thử lại sau ít phút."
	return "Thao tác không thành công. Vui lòng thử lại."


func _set_online(v: bool) -> void:
	if v != online:
		online = v
		connectivity.emit(v)


func _fail(code: int, msg: String) -> Dictionary:
	return {"ok": false, "code": code, "data": null, "error": msg}


## Identifies this app in the account's device list ("Thiết bị đăng nhập").
static func user_agent() -> String:
	var kind := "Mobile" if OS.has_feature("mobile") else "Desktop"
	return "ThueTab-App/1 (%s; %s)" % [OS.get_name(), kind]
