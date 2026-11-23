extends RefCounted

# The read-only door to Plaid for the house's money. The only calls it can make are the two in
# `PATHS`, POSTs of JSON to `HOST`: nothing that moves money, reads a balance at a price or asks the
# bank to refresh, and no link flow (the one existing link is the operator's; the account allows ten
# for ever, so linking stays a task of the server's repo).
#
# The credentials are read at each call and never kept, logged or put in an error: the env
# `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ACCESS_TOKEN`, else the machine secrets
# `$XDG_RUNTIME_DIR/agenix/plaid-client-id`, `plaid-secret`, `plaid-access-token`, else the
# same three keys (`client_id`, `secret`, `access_token`) of `user://house_plaid.json`, which the
# operator writes (0600) and the house only reads. An answer is `{"ok": reply}` or
# `{"error": "plaid", "code"}` (Plaid's own, e.g. ITEM_LOGIN_REQUIRED), `{"error": "http",
# "status"}`, `{"error": "transport"}`, `{"error": "no_credentials"}` or
# `{"error": "unexpected_reply"}`.
const HOST := "https://production.plaid.com"
const PATHS := ["/transactions/sync", "/accounts/get"]
const ENV := {
	"client_id": "PLAID_CLIENT_ID",
	"secret": "PLAID_SECRET",
	"access_token": "PLAID_ACCESS_TOKEN",
}
const FILES := {
	"client_id": "plaid-client-id",
	"secret": "plaid-secret",
	"access_token": "plaid-access-token",
}
const KEY_FILE := "user://house_plaid.json"

# a test's own credentials ({client_id, secret, access_token}); when set nothing else is read
var given: Dictionary = {}
var key_file := KEY_FILE
var host := HOST
# (url, body: String, cb(ok: bool, status: int, reply: String)); the Bank puts the network here
var http := Callable()


func access_token() -> String:
	return _secret("access_token")


# one page of /transactions/sync from `cursor` ("" for the first call), at most `count` changes
func sync(cursor: String, count: int, cb: Callable) -> void:
	var body := {"count": count}
	if cursor != "":
		body["cursor"] = cursor
	_post("/transactions/sync", body, cb, true)


# the accounts with their cached balances (/accounts/get, free): the list
func accounts(cb: Callable) -> void:
	_post(
		"/accounts/get",
		{},
		func(r: Dictionary) -> void:
			if r.has("ok") and not r["ok"].get("accounts") is Array:
				r = {"error": "unexpected_reply"}
			cb.call(r if r.has("error") else {"ok": r["ok"]["accounts"]}),
		true
	)


func _post(path: String, body: Dictionary, cb: Callable, with_token: bool) -> void:
	assert(path in PATHS)
	var client_id := _secret("client_id")
	var secret := _secret("secret")
	var token := _secret("access_token")
	if client_id == "" or secret == "" or (with_token and token == ""):
		cb.call_deferred({"error": "no_credentials"})
		return
	var sent := body.duplicate()
	sent["client_id"] = client_id
	sent["secret"] = secret
	if with_token:
		sent["access_token"] = token
	if not http.is_valid():
		cb.call_deferred({"error": "transport"})
		return
	http.call(
		host + path,
		JSON.stringify(sent),
		func(ok: bool, status: int, reply: String) -> void: cb.call(_answer(ok, status, reply))
	)


static func _answer(ok: bool, status: int, reply: String) -> Dictionary:
	if not ok:
		return {"error": "transport"}
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(reply) == OK else null
	if status == 200:
		return {"ok": parsed} if parsed is Dictionary else {"error": "unexpected_reply"}
	if parsed is Dictionary and parsed.get("error_code") is String:
		return {"error": "plaid", "code": parsed["error_code"]}
	return {"error": "http", "status": status}


func _secret(name: String) -> String:
	if not given.is_empty():
		return str(given.get(name, "")).strip_edges()
	var from_env := OS.get_environment(ENV[name]).strip_edges()
	if from_env != "":
		return from_env
	var run := OS.get_environment("XDG_RUNTIME_DIR")
	if run != "":
		var path := run.path_join("agenix").path_join(FILES[name])
		if FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path).strip_edges()
			if text != "":
				return text
	return _from_key_file(name)


func _from_key_file(name: String) -> String:
	if not FileAccess.file_exists(key_file):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(key_file)) != OK or not json.data is Dictionary:
		return ""
	var v: Variant = json.data.get(name)
	return v.strip_edges() if v is String else ""
