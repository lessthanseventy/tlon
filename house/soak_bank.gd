extends RefCounted

# The soak's check of the bank's one outward path: a refresh through the engine's own HTTP request,
# against a stub of Plaid on the soak's local server (the real Plaid is never reached): what it
# sends (the credentials in the body, none in the address), what it keeps, and that a house that
# may not go online asks nothing.
const Bank := preload("res://bank.gd")
const LocalList := preload("res://local_list.gd")
const CREDS := {"client_id": "cid-1", "secret": "sec-2", "access_token": "tok-3"}

var s
var t := 0.0


func _init(soak) -> void:
	s = soak


func _clock() -> float:
	return t


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	t = LocalList.wall(2026, 11, 20, 12)
	if not s._srv.is_listening():
		s._srv.listen(0, "127.0.0.1")
	var seen: Array = []
	s.stub = func(_method: String, path: String, body: Variant) -> Variant:
		if path == "/transactions/sync":
			seen.append(path)
			return {"code": 200, "body": _page(body)}
		if path == "/accounts/get":
			seen.append(path)
			return {"code": 200, "body": {"accounts": [_account()]}}
		return null
	var bank := Bank.new()
	bank.clock = Callable(self, "_clock")
	bank.plaid.given = CREDS.duplicate()
	bank.plaid.host = "http://127.0.0.1:%d" % s._srv.get_local_port()
	s.root.add_child(bank)

	var got := {}
	bank.refresh(func(r: Dictionary) -> void: got.merge(r))
	await s._until(func(): return not got.is_empty() or s._log.size() > 0, "the offline house asks")
	_eq(got, {"error": "transport"}, "a house that may not go online sends nothing")
	_eq(s._log.size(), 0, "and the stub saw nothing")

	bank.live = true
	got = {}
	bank.refresh(func(r: Dictionary) -> void: got.merge(r))
	await s._until(func(): return not got.is_empty(), "the refresh answers")
	_eq(got.has("ok"), true, "a refresh over HTTP")
	_eq(seen, ["/transactions/sync", "/accounts/get"], "a sync, then the accounts")
	var sync: Array = s._log.filter(func(l): return l[1] == "/transactions/sync")
	var body: Dictionary = JSON.parse_string(sync[0][2])
	_eq(
		[body["client_id"], body["secret"], body["access_token"]],
		["cid-1", "sec-2", "tok-3"],
		"keys in the body"
	)
	_eq(str(s._log.map(func(l): return l[1])).contains("tok-3"), false, "none in an address")
	_eq(bank.rows.keys(), ["t1"], "the row kept")
	_eq(bank.summary()["available"], 123456, "the balance kept, in cents")
	s.root.remove_child(bank)
	bank.free()


func _page(_body: Variant) -> Dictionary:
	return {
		"next_cursor": "c1",
		"has_more": false,
		"added":
		[
			{
				"transaction_id": "t1",
				"account_id": "a1",
				"amount": 12.34,
				"date": "2026-11-19",
				"name": "Cafe",
				"pending": false
			}
		],
		"modified": [],
		"removed": [],
	}


func _account() -> Dictionary:
	return {
		"account_id": "a1",
		"name": "Current",
		"type": "depository",
		"subtype": "checking",
		"balances": {"current": 1234.56, "available": 1234.56}
	}
