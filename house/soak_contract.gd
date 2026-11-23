extends "res://logic_local.gd"

# The cases of `home_contract.json` against `backend_local.gd` on a fixed clock: the server's codes,
# error lines and answer shapes, and each gap held to being true.
const BackendLocal := preload("res://backend_local.gd")
const CONTRACT := "res://home_contract.json"

var _types: Dictionary = {}
var _gaps: Dictionary = {}
var _ids: Dictionary = {}
var _hit: Dictionary = {}


func run() -> void:
	t = at(2026, 11, 18, 14)
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	_check_contract(not contract.is_empty(), "the contract file reads")
	_types = contract["types"]
	_gaps = contract["gaps"]
	var backend := BackendLocal.new()
	backend.setup("", Callable(self, "_clock"), 0.0, false)
	for route in contract["routes"]:
		for c in route["cases"]:
			_case(backend, route, c)
	for id in _gaps:
		_check_contract(
			_hit.has(id) or _gaps[id].get("untested", false), "gap %s is met by a case" % id
		)
	backend.free()


func _check_contract(ok: bool, what: String) -> void:
	s._check(ok, "contract: " + what)


func _case(backend: Node, route: Dictionary, c: Dictionary) -> void:
	if c.has("put_off"):
		var id: int = _ids[c["put_off"]]
		backend.list.things().filter(func(x): return x["id"] == id)[0]["state"] = "someday"
	var path: String = _fill(str(c.get("path", route["path"])))
	var body: Dictionary = _fill_body(c.get("body", {}))
	var answer: Dictionary = backend._route(str(route["method"]), path, body)
	var what := "%s %s: %s" % [route["method"], route["path"], c["name"]]
	var misses := _misses(answer, c)
	var gaps: Array = _gap_ids(c)
	for g in gaps:
		_check_contract(_gaps.has(g), "%s names a gap that is listed (%s)" % [what, g])
		_hit[g] = true
	if gaps.is_empty():
		_check_contract(misses.is_empty(), "%s: %s" % [what, "; ".join(misses)])
	else:
		_check_contract(
			not misses.is_empty(), "%s no longer differs, so its gap %s is gone" % [what, gaps]
		)
	if c.has("as") and answer["code"] == 200 and answer["body"] is Dictionary:
		_ids[str(c["as"])] = int(answer["body"]["id"])


func _gap_ids(c: Dictionary) -> Array:
	var g: Variant = c.get("gap")
	if g == null:
		return []
	return g if g is Array else [g]


func _fill(path: String) -> String:
	for k in _ids:
		path = path.replace("{%s}" % k, str(_ids[k]))
	return path


func _fill_body(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _fill_body(v[k])
		return out
	if (
		v is String
		and v.begins_with("{")
		and v.ends_with("}")
		and _ids.has(v.substr(1, v.length() - 2))
	):
		return _ids[v.substr(1, v.length() - 2)]
	return v


func _misses(answer: Dictionary, c: Dictionary) -> Array:
	var out: Array = []
	if answer["code"] != int(c["code"]):
		out.append("code %s, want %s" % [answer["code"], c["code"]])
		return out
	if c.has("error"):
		var line: Variant = answer["body"].get("error") if answer["body"] is Dictionary else null
		if line != c["error"]:
			out.append("error %s, want %s" % [line, c["error"]])
	if c.has("has") and answer["body"] is Dictionary:
		for k in c["has"]:
			if not str(c["has"][k]) in str(answer["body"].get(k)):
				out.append("%s lacks %s" % [k, c["has"][k]])
	if c.has("shape") and answer["code"] == 200:
		_fits(answer["body"], c["shape"], "body", out)
	return out


func _fits(v: Variant, shape: Variant, where: String, out: Array) -> void:
	if shape is String:
		if not _alternatives(v, shape, where):
			out.append("%s is %s, want %s" % [where, _name(v), shape])
	elif shape is Array:
		if not v is Array:
			out.append("%s is %s, want a list" % [where, _name(v)])
			return
		for i in v.size():
			_fits(v[i], shape[0], "%s[%d]" % [where, i], out)
	elif shape is Dictionary and shape.has("$or"):
		var tries: Array = []
		for alt in shape["$or"]:
			var sub: Array = []
			_fits(v, alt, where, sub)
			if sub.is_empty():
				return
			tries.append(sub)
		out.append(
			"%s fits none of its shapes (%s)" % [where, tries[0][0] if tries.size() > 0 else ""]
		)
	elif shape is Dictionary:
		if not v is Dictionary:
			out.append("%s is %s, want an object" % [where, _name(v)])
			return
		for k in shape:
			var key: String = str(k).trim_suffix("?")
			if not v.has(key):
				if not str(k).ends_with("?"):
					out.append("%s lacks %s" % [where, key])
				continue
			_fits(v[key], shape[k], "%s.%s" % [where, key], out)
		for k in v:
			if not shape.has(k) and not shape.has(str(k) + "?"):
				out.append("%s has the extra key %s" % [where, k])


func _alternatives(v: Variant, shape: String, where: String) -> bool:
	for alt in shape.split("|"):
		if alt.begins_with("@"):
			var sub: Array = []
			_fits(v, _types[alt.substr(1)], where, sub)
			if sub.is_empty():
				return true
		elif _is(v, alt):
			return true
	return false


func _is(v: Variant, name: String) -> bool:
	var kinds := {
		"int": [TYPE_INT],
		"num": [TYPE_INT, TYPE_FLOAT],
		"str": [TYPE_STRING],
		"bool": [TYPE_BOOL],
		"null": [TYPE_NIL],
		"obj": [TYPE_DICTIONARY],
	}
	if name == "any":
		return true
	if name == "int" and typeof(v) == TYPE_FLOAT:
		return v == floor(v)
	return kinds.has(name) and typeof(v) in kinds[name]


func _name(v: Variant) -> String:
	return type_string(typeof(v))
