extends RefCounted

# One-shot move of the server's home into the house's own list: the answer of `GET /api/home/export`
# (read-only on the server, which keeps everything) put into a `local_list.gd` document. Every
# imported row carries `origin` ("server:<id>"), so a second run adds nothing. Ids are the list's
# own; a step's project and a note's agenda are mapped. `run` always works on a copy of the list,
# so a dry run and a write take the same path and the dry run's report is what the write does.
const KINDS := ["todo", "reminder", "note", "waiting", "project"]
const PILES := ["agenda", "person", "door"]
const STATES := ["open", "someday", "done", "dropped"]
const SETTINGS := ["telegram_list_at", "telegram_morning_at"]


# rows by kind: the plain kinds as they are, piles by their own kind, "proposals" apart
static func counts(things: Array, agendas: Array) -> Dictionary:
	var out := {}
	for t in things:
		out[t["kind"]] = int(out.get(t["kind"], 0)) + 1
	for a in agendas:
		var kind := str(a.get("kind", "agenda"))
		out[kind] = int(out.get(kind, 0)) + 1
	return out


# an error line for an export that is not whole or not the one it says; "" when it can be imported
static func refusal(export: Dictionary) -> String:
	if export.get("v") != 1.0 and export.get("v") != 1:
		return "the export is not version 1"
	var things: Variant = export.get("things")
	var agendas: Variant = export.get("agendas")
	if not (things is Array and agendas is Array and export.get("counts") is Dictionary):
		return "the export has no things, agendas and counts"
	if things.is_empty() and agendas.is_empty():
		return "the export holds no rows: nothing was read, nothing is imported"
	for t in things:
		if not (t is Dictionary and t.get("id") != null and t.get("kind") in KINDS):
			return "a thing of the export has no id or no known kind: %s" % str(t)
		if not (t.get("text") is String and t.get("state") in STATES):
			return "thing %s has no text or no known state" % str(t["id"])
	for a in agendas:
		if not (a is Dictionary and a.get("id") != null and a.get("kind") in PILES):
			return "an agenda of the export has no id or no known kind: %s" % str(a)
		if not a.get("name") is String:
			return "agenda %s has no name" % str(a["id"])
	var got := counts(things, agendas)
	var said: Dictionary = export["counts"]
	for kind in got:
		if int(said.get(kind, -1)) != int(got[kind]):
			return (
				"the server counts %s %s, the export holds %d"
				% [str(said.get(kind)), kind, got[kind]]
			)
	return ""


# the report: {"error"} and nothing changed, or {"server", "added", "already", "local": counts by
# kind (local: the imported rows the list holds), "proposals": n not carried, "settings": {...}}.
# `write` puts the copy in the list, saves it and answers the same report.
static func run(list: RefCounted, export: Dictionary, write: bool) -> Dictionary:
	var why := refusal(export)
	if why != "":
		return {"error": why}
	var doc: Dictionary = list.doc.duplicate(true)
	var things: Array = export["things"]
	var agendas: Array = export["agendas"]
	var added := {}
	var already := {}
	var agenda_ids := {}
	var thing_ids := {}
	var next := int(doc["next_id"])
	for a in agendas:
		var key := "server:%d" % int(a["id"])
		var local := _pile_of(doc, key, a)
		if not local.is_empty():
			agenda_ids[int(a["id"])] = int(local["id"])
			already[a["kind"]] = int(already.get(a["kind"], 0)) + 1
			if local.get("origin") == null:
				local["origin"] = key
			continue
		agenda_ids[int(a["id"])] = next
		doc["agendas"].append(_agenda(a, next, key))
		added[a["kind"]] = int(added.get(a["kind"], 0)) + 1
		next += 1
	var fresh: Array = []
	for t in things:
		var key := "server:%d" % int(t["id"])
		var have := _thing_of(doc, key)
		if not have.is_empty():
			thing_ids[int(t["id"])] = int(have["id"])
			already[t["kind"]] = int(already.get(t["kind"], 0)) + 1
		else:
			thing_ids[int(t["id"])] = next
			fresh.append(t)
			next += 1
	for t in fresh:
		var made := _thing(t, int(thing_ids[int(t["id"])]), "server:%d" % int(t["id"]))
		for link in ["project_id", "agenda_id"]:
			if t.get(link) == null:
				continue
			var table: Dictionary = thing_ids if link == "project_id" else agenda_ids
			if not table.has(int(t[link])):
				return {
					"error":
					(
						"thing %d names %s %d, which the export does not hold"
						% [int(t["id"]), link, int(t[link])]
					)
				}
			made[link] = table[int(t[link])]
		doc["things"].append(made)
		added[t["kind"]] = int(added.get(t["kind"], 0)) + 1
	doc["next_id"] = next
	var settings := {}
	for key in SETTINGS:
		if export.get("settings") is Dictionary and export["settings"].get(key) is String:
			settings[key] = export["settings"][key]
	var report := {
		"server": counts(things, agendas),
		"added": added,
		"already": already,
		"local": _imported(doc),
		"proposals":
		(export["proposals"] as Array).size() if export.get("proposals") is Array else 0,
		"settings": settings,
	}
	if write:
		list.doc = doc
		list.save()
	return report


# the pile this one already is here: by origin, else a hand-made one (no origin yet) of the same
# kind and name (the door is one only)
static func _pile_of(doc: Dictionary, key: String, a: Dictionary) -> Dictionary:
	for x in doc["agendas"]:
		if x.get("origin") == key:
			return x
	for x in doc["agendas"]:
		var kind := str(x.get("kind", "agenda"))
		if (
			x.get("origin") == null
			and kind == a["kind"]
			and (kind == "door" or str(x["name"]).to_lower() == str(a["name"]).to_lower())
		):
			return x
	return {}


static func _thing_of(doc: Dictionary, key: String) -> Dictionary:
	for t in doc["things"]:
		if t.get("origin") == key:
			return t
	return {}


static func _agenda(a: Dictionary, id: int, key: String) -> Dictionary:
	var out := {
		"id": id,
		"name": a["name"],
		"told_for": a.get("told_for"),
		"every": a.get("every"),
		"every_day": a.get("every_day"),
		"next_at": a.get("next_at"),
		"origin": key,
	}
	if a["kind"] != "agenda":
		out["kind"] = a["kind"]
	if a["kind"] == "person":
		out["birthday"] = a.get("birthday")
	return out


static func _thing(t: Dictionary, id: int, key: String) -> Dictionary:
	return {
		"id": id,
		"kind": t["kind"],
		"text": t["text"],
		"state": t["state"],
		"since": t.get("since"),
		"due_at": t.get("due_at"),
		"every": t.get("every"),
		"every_day": t.get("every_day"),
		"told_at": t.get("told_at"),
		"nudges": int(t.get("nudges", 0)),
		"project_id": null,
		"who": t.get("who"),
		"plan": t.get("plan", []),
		"done_at": t.get("done_at"),
		"dropped_at": t.get("dropped_at"),
		"hidden_until": t.get("hidden_until"),
		"origin": key,
	}


# the rows the server gave, as the list holds them now
static func _imported(doc: Dictionary) -> Dictionary:
	return counts(
		doc["things"].filter(func(t): return t.get("origin") != null),
		doc["agendas"].filter(func(a): return a.get("origin") != null)
	)
