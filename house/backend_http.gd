extends "res://backend.gd"

# The routes over HTTP, to the tlon server at `base`.
var base := "http://127.0.0.1:4040"


func fetch(path: String, cb: Callable, timeout: float = 8.0) -> void:
	_request(base + path, HTTPClient.METHOD_GET, "", cb, timeout)


func send(path: String, body: Dictionary, cb: Callable, timeout: float = 6.0) -> void:
	_request(base + path, HTTPClient.METHOD_POST, JSON.stringify(body), cb, timeout)


func check(url: String, cb: Callable) -> void:
	_request(
		url + "/api/home",
		HTTPClient.METHOD_GET,
		"",
		func(reached: bool, code: int, _parsed: Variant) -> void: cb.call(reached and code == 200),
		4.0
	)


func _request(url: String, method: int, payload: String, cb: Callable, timeout: float) -> void:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			cb.call(
				result == HTTPRequest.RESULT_SUCCESS,
				code,
				JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else null
			)
	)
	var headers := ["Content-Type: application/json"] if method == HTTPClient.METHOD_POST else []
	if req.request(url, headers, method, payload) != OK:
		req.queue_free()
		cb.call_deferred(false, 0, null)
