extends Node

# Where the house's list lives: the operator API's routes, answered by a tlon server
# (`backend_http.gd`) or by the house itself (`backend_local.gd`). Callers hold one and never ask
# which: `fetch` and `send` take a route and answer `cb(reached: bool, code: int, parsed: Variant)`
# on a later frame, never inside the call.
#
# Two seams for what comes later: `told` is a reminder that was just told (the ring's moment) and
# `replied` a loose line and the answer made to it; a chat that talks over Telegram listens to both.
# `changed` says the list moved by itself (a reminder came due) and the room should be read again.
signal told(row: Dictionary)
signal replied(said: String, reply: String)
signal changed

var local := false


func fetch(_path: String, cb: Callable, _timeout: float = 8.0) -> void:
	cb.call_deferred(false, 0, null)


func send(_path: String, _body: Dictionary, cb: Callable, _timeout: float = 6.0) -> void:
	cb.call_deferred(false, 0, null)


# is the server at `url` there: cb(ok)
func check(_url: String, cb: Callable) -> void:
	cb.call_deferred(false)
