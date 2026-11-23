extends Node

# What the house knows of the operator's bank, read-only through Plaid (`bank_plaid.gd`), kept in
# one file, `user://house_bank.json` (0600, the token never in it): the transactions of the last
# 800 days (`rows`, by Plaid's transaction id, as `Recurring.txn` reads them), the sync cursor, the
# accounts with their cached balances, when they were read, the summary's dated part and the
# notices cleared. A refresh syncs and then writes everything at once, so one that fails anywhere
# keeps nothing and the next starts from the cursor this one began with.
#
# `summary()` is what `GET /api/home` says as `money`, worked out once per refresh from the rows
# with no call to Plaid (`bank_recurring.gd`); the part that depends on today (due this week, the
# next deposit) is stored with the day it was worked out for and worked out again from the rows
# when read on another day. It is null with no token or nothing read yet. Every account is listed;
# the spendable ones are the depository accounts of subtype checking, summed into `balance` and
# `available`, and savings and credit accounts are never counted. All amounts are integers of cents.
# Nothing is asked of Plaid unless `live`.
signal refreshed

const Plaid := preload("res://bank_plaid.gd")
const Recurring := preload("res://bank_recurring.gd")
const Projecting := preload("res://bank_projection.gd")
const U := preload("res://bank_util.gd")

const STORE := "user://house_bank.json"
const KEEP_DAYS := 800
const PAGE := 500
const PAGES := 40
const RETRIES := 2
const MUTATION := "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION"
const FIRST := 5.0
const EVERY := 900.0
const TIMEOUT := 30.0

var plaid := Plaid.new()
var store := STORE
var persist := false
# false: no request is ever made (a staged run reads what is kept and nothing more)
var live := false
# the house's local wall clock, seconds; `bias` is the zone's offset from UTC
var clock := Callable()
var bias := 0.0
var state: Dictionary = {}
var rows: Dictionary = {}

var _busy := false
var _due := FIRST
var _txns: Variant = null


func _init() -> void:
	plaid.http = _http


func now() -> float:
	return clock.call() if clock.is_valid() else Time.get_unix_time_from_system()


func today() -> String:
	return U.date_of_unix(now())


# whether the bank source is on: a token is there to read with
func enabled() -> bool:
	return plaid.access_token() != ""


func load_file() -> void:
	state = {}
	rows = {}
	_txns = null
	if not (persist and FileAccess.file_exists(store)):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(store)) != OK or not json.data is Dictionary:
		return
	var d: Dictionary = json.data
	for r in d.get("transactions", []):
		if r is Dictionary and r.get("id") is String and r.get("cents") != null:
			var row: Dictionary = r.duplicate()
			row["cents"] = int(row["cents"])
			rows[row["id"]] = row
	for key in ["cursor", "accounts", "as_of", "summary", "seen"]:
		if d.has(key):
			state[key] = d[key]
	if state.has("accounts"):
		for a in state["accounts"]:
			for k in ["current", "available"]:
				if a.get(k) != null:
					a[k] = int(a[k])


func _save() -> void:
	if not persist:
		return
	var out := state.duplicate()
	out["transactions"] = rows.values()
	var tmp := store + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	f.store_string(JSON.stringify(out))
	f.close()
	DirAccess.rename_absolute(tmp, store)


# the transactions kept, as `Recurring.txn` reads them, transfers between the accounts left out
func transactions() -> Array:
	if _txns == null:
		var ordered := U.sort_by(
			rows.values(), func(r: Dictionary) -> Array: return [r["date"], r["id"]]
		)
		var parsed: Array = []
		for r in ordered:
			var t: Variant = Recurring.txn(r)
			if t != null:
				parsed.append(t)
		_txns = Recurring.without_transfers(parsed)
	return _txns


func _data() -> Variant:
	var accounts: Variant = state.get("accounts")
	if enabled() and accounts is Array and not accounts.is_empty():
		return {"transactions": transactions(), "accounts": accounts}
	return null


func _projected(fun: Callable) -> Dictionary:
	var data: Variant = _data()
	return {"error": "no_data"} if data == null else fun.call(data)


# the balance day by day to `until` (an ISO date); {"error": "no_data"} with the source off or
# nothing stored
func forecast(until: String) -> Dictionary:
	return _projected(
		func(d: Dictionary) -> Dictionary: return Projecting.forecast(d, today(), until)
	)


# what is safe to spend a day until the next deposit, today's spend and the last two weeks' top
# spends (`Projecting.budget`); {"error": "no_data"} as `forecast`
func budget() -> Dictionary:
	return _projected(func(d: Dictionary) -> Dictionary: return Projecting.budget(d, today()))


func afford(cents: Variant, on: Variant = null, cushion: Variant = null) -> Dictionary:
	var opts := {} if cushion == null else {"cushion_cents": cushion}
	return _projected(
		func(d: Dictionary) -> Dictionary: return Projecting.afford(d, today(), cents, on, opts)
	)


func what_if(changes: Array, until: String) -> Dictionary:
	return _projected(
		func(d: Dictionary) -> Dictionary: return Projecting.what_if(d, today(), changes, until)
	)


func history(query: Dictionary) -> Dictionary:
	return _projected(func(d: Dictionary) -> Dictionary: return Projecting.history(d, query))


func merchants() -> Dictionary:
	return _projected(
		func(d: Dictionary) -> Dictionary: return {"ok": Projecting.merchants(d, today())}
	)


func subscriptions() -> Dictionary:
	return _projected(
		func(d: Dictionary) -> Dictionary: return {"ok": Projecting.subscriptions(d, today())}
	)


# {balance, available, as_of, due_this_week, next_deposit, accounts}, null when the source is off or
# nothing was read yet
func summary() -> Variant:
	var accounts: Variant = state.get("accounts")
	if not enabled() or not accounts is Array or accounts.is_empty() or not state.has("as_of"):
		return null
	var spendable: Array = accounts.filter(func(a: Dictionary) -> bool: return U.spendable(a))
	var dated := _dated(state.get("summary"), accounts, today())
	return {
		"balance": U.total(spendable, func(a: Dictionary) -> Variant: return a["current"]),
		"available": U.spendable_available(accounts),
		"as_of": state["as_of"],
		"due_this_week": dated["due_this_week"],
		"next_deposit": dated["next_deposit"],
		"accounts": accounts.map(_listed),
	}


static func _listed(a: Dictionary) -> Dictionary:
	return {
		"id": a["id"],
		"name": a["name"],
		"type": a["type"],
		"subtype": a["subtype"],
		"balance": a["current"],
		"available": a["available"],
		"spendable": U.spendable(a),
	}


func _dated(kept: Variant, accounts: Array, day: String) -> Dictionary:
	if kept is Dictionary and kept.get("for") == day:
		return {"due_this_week": kept["due_this_week"], "next_deposit": kept["next_deposit"]}
	return _fresh(accounts, day)


func _item(series: Dictionary) -> Dictionary:
	return {"name": series["label"], "amount": series["amount"], "on": series["next"]}


func _fresh(accounts: Array, day: String) -> Dictionary:
	var txns := transactions()
	var ids: Array = []
	for a in accounts:
		if U.spendable(a):
			ids.append(a["id"])
	var due := Recurring.due_within(Recurring.series(txns, "out"), day, 6).map(_item)
	var deposit: Variant = null
	for s in Recurring.series(txns, "in"):
		if s["account_id"] in ids and s["next"] >= day:
			deposit = _item(s)
			break
	return {"due_this_week": due, "next_deposit": deposit}


# what the engine notes on `today` that is no one's to do, minus the cleared ones:
# [{key, kind "new"|"price", text, why}]
func notices() -> Array:
	var day := today()
	var out := Recurring.series(transactions(), "out")
	var all: Array = []
	for s in Recurring.new_series(out, day):
		all.append(_notice("new", "bank:new:" + _hash(s["key"]), _new_text(s), _new_why(s)))
	for s in Recurring.price_changes(out, day):
		var word := "up" if s["amount"] > s["was"] else "down"
		var key := "bank:price:%s:%d" % [_hash(s["key"]), s["amount"]]
		var text := (
			"%s went %s from %s to %s" % [s["label"], word, U.money(s["was"]), U.money(s["amount"])]
		)
		var why := "%s, the last on %s" % [s["period"], U.day_short(s["last"])]
		all.append(_notice("price", key, text, why))
	var cleared: Array = state.get("seen", [])
	return all.filter(func(n: Dictionary) -> bool: return not n["key"] in cleared)


func _notice(kind: String, key: String, text: String, why: String) -> Dictionary:
	return {"key": key, "kind": kind, "text": text, "why": why}


func _new_text(s: Dictionary) -> String:
	return (
		"%s looks like a new subscription: %s %s" % [s["label"], U.money(s["amount"]), s["period"]]
	)


func _new_why(s: Dictionary) -> String:
	return "three steady charges, the last on %s" % U.day_short(s["last"])


static func _hash(key: String) -> String:
	return key.sha256_text().substr(0, 16)


# clear the notice `key` for good: false when it is not a `bank:new:` or `bank:price:` key
func see(key: Variant) -> bool:
	if not (key is String and (key.begins_with("bank:new:") or key.begins_with("bank:price:"))):
		return false
	var cleared: Array = state.get("seen", [])
	if not key in cleared:
		cleared.append(key)
		cleared.sort()
		state["seen"] = cleared
		_save()
	return true


func _process(_dt: float) -> void:
	step()


# a refresh at the start and then every `EVERY` seconds, never oftener; a failure waits for the next
func step() -> void:
	if not live or _busy:
		return
	_due -= get_process_delta_time()
	if _due <= 0.0:
		_due = EVERY
		if enabled():
			refresh()


# sync the transactions and read the accounts, then keep both with the new cursor:
# `cb({"ok": state})` or the first error of `bank_plaid.gd`, with nothing kept
func refresh(cb: Callable = Callable()) -> void:
	if _busy:
		return
	_busy = true
	var start := str(state.get("cursor", ""))
	_sync(
		start,
		RETRIES,
		func(synced: Dictionary) -> void:
			if synced.has("error"):
				_over(synced, cb)
				return
			plaid.accounts(func(got: Dictionary) -> void: _apply(synced["ok"], got, cb))
	)


func _over(result: Dictionary, cb: Callable) -> void:
	_busy = false
	if cb.is_valid():
		cb.call(result)
	if result.has("ok"):
		refreshed.emit()


func _sync(start: String, retries: int, cb: Callable) -> void:
	_pages(
		start,
		{"cursor": start, "rows": [], "removed": []},
		PAGES,
		func(r: Dictionary) -> void:
			if r.get("error") == "plaid" and r.get("code") == MUTATION and retries > 0:
				_sync(start, retries - 1, cb)
			else:
				cb.call(r)
	)


func _pages(cursor: String, acc: Dictionary, left: int, cb: Callable) -> void:
	if left == 0:
		cb.call({"error": "too_many_pages"})
		return
	plaid.sync(
		cursor,
		PAGE,
		func(r: Dictionary) -> void:
			if r.has("error"):
				cb.call(r)
				return
			var page: Dictionary = r["ok"]
			if not page.get("next_cursor") is String:
				cb.call({"error": "unexpected_reply"})
				return
			for t in _list(page.get("added")) + _list(page.get("modified")):
				acc["rows"].append_array(_row(t))
			for t in _list(page.get("removed")):
				if t is Dictionary and t.get("transaction_id") is String:
					acc["removed"].append(t["transaction_id"])
			acc["cursor"] = page["next_cursor"]
			if page.get("has_more") == true:
				_pages(page["next_cursor"], acc, left - 1, cb)
			else:
				cb.call({"ok": acc})
	)


static func _list(items: Variant) -> Array:
	return items if items is Array else []


# a Plaid transaction as the stored row, in an array (empty when it does not read)
static func _row(t: Variant) -> Array:
	if not (t is Dictionary and t.get("transaction_id") is String):
		return []
	var cents: Variant = U.cents_of(t.get("amount"))
	if cents == null or not t.get("date") is String or not U.valid(t["date"]):
		return []
	return [
		{
			"id": t["transaction_id"],
			"account_id": t.get("account_id"),
			"cents": cents,
			"date": t["date"],
			"name": t.get("name"),
			"merchant": t.get("merchant_name"),
			"pending": t.get("pending") == true,
		}
	]


static func _account(a: Variant) -> Variant:
	if not (a is Dictionary and a.get("account_id") is String):
		return null
	var balances: Variant = a.get("balances")
	var b: Dictionary = balances if balances is Dictionary else {}
	return {
		"id": a["account_id"],
		"name": U.line(a.get("name"), 40),
		"type": a.get("type"),
		"subtype": a.get("subtype"),
		"current": U.cents_of(b.get("current")),
		"available": U.cents_of(b.get("available")),
	}


func _apply(changes: Dictionary, got: Dictionary, cb: Callable) -> void:
	if got.has("error"):
		_over(got, cb)
		return
	var accounts: Array = []
	for a in got["ok"]:
		var account: Variant = _account(a)
		if account != null:
			accounts.append(account)
	var day := today()
	for r in changes["rows"]:
		rows[r["id"]] = r
	for id in changes["removed"]:
		rows.erase(id)
	var oldest := U.add(day, -KEEP_DAYS)
	for id in rows.keys():
		if rows[id]["date"] < oldest:
			rows.erase(id)
	_txns = null
	state["cursor"] = changes["cursor"]
	state["accounts"] = accounts
	state["as_of"] = Time.get_datetime_string_from_unix_time(int(now() - bias)) + "Z"
	state["summary"] = _stored(_fresh(accounts, day), day)
	_save()
	_over({"ok": state}, cb)


static func _stored(fresh: Dictionary, day: String) -> Dictionary:
	return {
		"for": day,
		"due_this_week": fresh["due_this_week"],
		"next_deposit": fresh["next_deposit"],
	}


func _http(url: String, body: String, cb: Callable) -> void:
	if not live or not is_inside_tree():
		cb.call_deferred(false, 0, "")
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, reply: PackedByteArray) -> void:
			req.queue_free()
			cb.call(result == HTTPRequest.RESULT_SUCCESS, code, reply.get_string_from_utf8())
	)
	if req.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		cb.call_deferred(false, 0, "")
