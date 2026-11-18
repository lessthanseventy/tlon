extends RefCounted

# What the cards put in and change: the calendar (a month, a day, its things, add), the clock's
# timers, the board (notes, projects, waiting-ons, someday) and the "what now" slip. It builds the
# blocks `card.gd` draws and turns a click's act into a form to open, a request to send or a thing
# done or deleted (told to the home's `acted`).
signal form_wanted(mode: String, spec: Dictionary)
signal post(path: String, body: Dictionary)

const Card := preload("res://card.gd")
const Sure := preload("res://sure.gd")
const Settings := preload("res://settings.gd")
const TABS := {"notes": "Notes", "projects": "Projects", "waiting": "Waiting", "someday": "Someday"}
const SHOWN := 6

var waiting: Array = []
var someday: Array = []
var projects: Array = []
var note_rows: Array = []
var mo := 0
var day := 0
var tab := "notes"
var proj := 0
var flash := ""
var pick := {}
var say := ""

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()


func setup(home) -> void:
	_hw = weakref(home)


func set_data(d: Dictionary) -> void:
	waiting = d.get("waiting", [])
	someday = d.get("someday", [])
	projects = d.get("projects", [])
	note_rows = d.get("note_rows", [])


func reset() -> void:
	mo = 0
	day = 0
	proj = 0
	flash = ""


func today() -> Dictionary:
	var d := Time.get_datetime_dict_from_unix_time(int(h._now_local()))
	return {"y": d["year"], "m": d["month"], "d": d["day"]}


# the month the calendar shows, `mo` months from this one
func shown() -> Dictionary:
	var t := today()
	var idx: int = int(t["y"]) * 12 + int(t["m"]) - 1 + mo
	return {"y": idx / 12, "m": idx % 12 + 1, "today": t["d"] if mo == 0 else 0}


func find(id: int) -> Dictionary:
	for list in [h.open, h.coming, waiting, someday, projects]:
		for row in list:
			if int(row["id"]) == id:
				return row
	return {}


func edit(id: int) -> void:
	var row := find(id)
	if row.is_empty():
		return
	var due := -1.0
	if row.get("due_at") != null:
		due = h._due(row)
	form_wanted.emit("edit", {"row": row, "due": due})


func _add(spec: Dictionary) -> void:
	form_wanted.emit("new", spec)


func _ago(row: Dictionary) -> String:
	return "" if row.get("since") == null else h._ago(str(row["since"]))


func _head() -> Array:
	return [{"t": "dim", "text": flash}] if flash != "" else []


# the calendar: the month with its arrows, a day's things when one is picked, else what is coming
func calendar_blocks() -> Array:
	var s := shown()
	var from := Card.unix(s["y"], s["m"], 1)
	var to := Card.unix(int(s["y"]) + int(s["m"]) / 12, int(s["m"]) % 12 + 1, 1)
	var marks := {}
	var by_day := {}
	for item in h._timed():
		for at in Card.occurrences(h._due(item), h._every(item), from, to):
			var d: int = Time.get_datetime_dict_from_unix_time(int(at))["day"]
			marks[d] = true
			by_day[d] = by_day.get(d, []) + [[at, item]]
	var blocks: Array = _head()
	(
		blocks
		. append(
			{
				"t": "month",
				"year": s["y"],
				"month": s["m"],
				"today": s["today"],
				"marks": marks,
				"pick": true,
				"sel": day,
			}
		)
	)
	if day > 0:
		var wd: int = (
			Time.get_datetime_dict_from_unix_time(int(Card.unix(s["y"], s["m"], day)))["weekday"]
		)
		blocks.append(
			{
				"t": "title",
				"text": "%s %d %s" % [h.DAYS[wd], day, Card.MONTHS[int(s["m"]) - 1].substr(0, 3)]
			}
		)
		var entries: Array = by_day.get(day, [])
		entries.sort_custom(func(a, b): return a[0] < b[0])
		for e in entries:
			blocks.append(
				{"t": "row", "text": _line(e[0], e[1]), "act": "edit:%d" % int(e[1]["id"])}
			)
		if entries.is_empty():
			blocks.append({"t": "dim", "text": "nothing that day"})
		blocks.append({"t": "buttons", "items": [{"label": "add", "act": "add_day"}]})
	else:
		blocks.append({"t": "title", "text": "Coming up"})
		var next: Array = h._upcoming(h.coming.filter(func(i): return i.get("due_at") != null), 5)
		for item in next:
			blocks.append(
				{
					"t": "row",
					"text": _line(h._due(item), item, true),
					"act": "edit:%d" % int(item["id"])
				}
			)
		if next.is_empty():
			blocks.append({"t": "text", "text": "Nothing coming up."})
		blocks.append({"t": "buttons", "items": [{"label": "add", "act": "add_day"}]})
	if h.finds.is_birthday():
		blocks.append({"t": "foot", "text": "happy birthday" + ("." if Settings.person == "" else ", " + Settings.person + ".")})
	elif h.finds.birthday == "":
		blocks.append({"t": "foot", "text": "today is my birthday", "act": "birthday"})
	return blocks


func _line(at: float, item: Dictionary, with_day: bool = false) -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(at))
	var line: String = h._stamp(at) if with_day else "%02d:%02d" % [t["hour"], t["minute"]]
	line += "  " + str(item["text"])
	return line if h._every(item) == "" else line + "  (%s)" % h._repeats(item)


func clock_blocks(base: Array) -> Array:
	return (
		_head()
		+ base
		+ [
			{"t": "gap"},
			{"t": "dim", "text": "A timer"},
			{
				"t": "buttons",
				"items":
				[
					{"label": "in 10 min", "act": "timer:10"},
					{"label": "30 min", "act": "timer:30"},
					{"label": "1 h", "act": "timer:60"},
					{"label": "named...", "act": "timer_named"},
				]
			}
		]
	)


func board_blocks() -> Array:
	var blocks: Array = _head()
	var items: Array = []
	for t in TABS:
		items.append({"label": TABS[t], "act": "tab:" + t, "on": t == tab, "s": 13})
	blocks.append({"t": "buttons", "items": items})
	match tab:
		"projects":
			blocks += _projects_blocks()
		"waiting":
			blocks += _waiting_blocks()
		"someday":
			blocks += _someday_blocks()
		_:
			blocks += _notes_blocks()
	return blocks


func _more(list: Array) -> Array:
	return (
		[{"t": "dim", "text": "and %d more" % (list.size() - SHOWN)}] if list.size() > SHOWN else []
	)


func _x(act: String) -> Dictionary:
	return {"label": "sure?" if h.sure.armed(act) else "x", "act": act}


func _notes_blocks() -> Array:
	var rows: Array = note_rows
	if rows.is_empty():
		rows = h.notes.map(func(n): return {"id": 0, "text": n})
	var per: int = h.NOTES_PER_PAGE
	var pages := maxi(1, ceili(rows.size() / float(per)))
	h.card.page = clampi(h.card.page, 0, pages - 1)
	var blocks: Array = []
	for r in rows.slice(h.card.page * per, (h.card.page + 1) * per):
		var id := int(r["id"])
		(
			blocks
			. append(
				{
					"t": "row",
					"text": "- " + str(r["text"]),
					"act": "nop",
					"marks": [_x("note_del:%d" % id)] if id > 0 else [],
				}
			)
		)
	if rows.is_empty():
		blocks.append({"t": "text", "text": "Nothing is pinned."})
	var items: Array = [{"label": "add a note", "act": "note_add"}]
	if pages > 1:
		blocks.append({"t": "dim", "text": "page %d of %d" % [h.card.page + 1, pages]})
		items += [{"label": "<", "act": "prev"}, {"label": ">", "act": "next"}]
	blocks.append({"t": "buttons", "items": items})
	return blocks


func _projects_blocks() -> Array:
	if proj > 0:
		return _project_blocks()
	var blocks: Array = []
	for p in projects.slice(0, SHOWN):
		var next: Variant = p.get("next")
		var text := str(p["text"])
		if next is Dictionary:
			text += "  -  " + str(next["text"])
		blocks.append({"t": "row", "text": text, "act": "proj:%d" % int(p["id"])})
	if projects.is_empty():
		blocks.append({"t": "text", "text": "No project yet."})
	blocks += _more(projects)
	blocks.append({"t": "buttons", "items": [{"label": "new project", "act": "proj_new"}]})
	return blocks


func _project_blocks() -> Array:
	var p := find(proj)
	if p.is_empty() or not projects.has(p):
		proj = 0
		return _projects_blocks()
	var blocks: Array = [{"t": "title", "text": str(p["text"])}]
	var next: Variant = p.get("next")
	if next is Dictionary:
		(
			blocks
			. append(
				{
					"t": "row",
					"text": "now: " + str(next["text"]),
					"act": "edit:%d" % int(next["id"]),
					"marks":
					[
						{"label": "Done", "act": "done:%d" % int(next["id"])},
						_x("del:%d" % int(next["id"]))
					],
				}
			)
		)
	else:
		blocks.append({"t": "dim", "text": "no step open"})
	var plan: Array = p.get("plan", [])
	for i in mini(plan.size(), SHOWN):
		var marks: Array = [{"label": "^", "act": "up:%d" % i}, {"label": "v", "act": "dn:%d" % i}]
		marks.append({"label": "x", "act": "rm:%d" % i})
		blocks.append({"t": "row", "text": "then " + str(plan[i]), "act": "nop", "marks": marks})
	blocks += _more(plan)
	for text in p.get("steps_done", []).slice(-3):
		blocks.append({"t": "row", "text": "done: " + str(text), "act": "nop", "dim": true})
	var delete := "Delete for good?" if h.sure.armed("del:%d" % proj) else "Delete"
	(
		blocks
		. append(
			{
				"t": "buttons",
				"items":
				[
					{"label": "add a step", "act": "step_add"},
					{"label": "finish project", "act": "done:%d" % proj},
					{"label": delete, "act": "del:%d" % proj},
					{"label": "back", "act": "tab:projects"},
				]
			}
		)
	)
	return blocks


func _waiting_blocks() -> Array:
	var blocks: Array = []
	for w in waiting.slice(0, SHOWN):
		var id := int(w["id"])
		var text := "%s: %s" % [w.get("who", "?"), w["text"]]
		var ago := _ago(w)
		(
			blocks
			. append(
				{
					"t": "row",
					"text": text if ago == "" else "%s  (%s)" % [text, ago],
					"act": "edit:%d" % id,
					"marks": [{"label": "got it", "act": "done:%d" % id}, _x("del:%d" % id)],
				}
			)
		)
	if waiting.is_empty():
		blocks.append({"t": "text", "text": "Nobody is owing you."})
	blocks += _more(waiting)
	blocks.append({"t": "buttons", "items": [{"label": "add", "act": "wait_add"}]})
	return blocks


func _someday_blocks() -> Array:
	var blocks: Array = []
	for s in someday.slice(0, SHOWN):
		var id := int(s["id"])
		(
			blocks
			. append(
				{
					"t": "row",
					"text": str(s["text"]),
					"act": "nop",
					"marks": [{"label": "bring back", "act": "revive:%d" % id}, _x("del:%d" % id)],
				}
			)
		)
	if someday.is_empty():
		blocks.append({"t": "text", "text": "Nothing is put off."})
	blocks += _more(someday)
	return blocks


# the "what now" slip
func pick_blocks() -> Array:
	var blocks: Array = _head()
	if pick.is_empty():
		return (
			blocks + [{"t": "title", "text": "Right now"}, {"t": "text", "text": str(pick_say())}]
		)
	blocks.append({"t": "title", "text": "Right now"})
	blocks.append({"t": "text", "text": str(pick["text"])})
	if pick.get("why") != null and str(pick["why"]) != "":
		blocks.append({"t": "dim", "text": str(pick["why"])})
	var id := int(pick["id"])
	(
		blocks
		. append(
			{
				"t": "buttons",
				"items":
				[
					{"label": "Done", "act": "pk_done"},
					{"label": "Something else", "act": "pk_else"},
					{"label": "Not today", "act": "pk_not"},
					{
						"label": "Delete for good?" if h.sure.armed("del:%d" % id) else "Delete",
						"act": "pk_del"
					},
				]
			}
		)
	)
	return blocks


func pick_say() -> String:
	return say if say != "" else "Nothing to pick."


# what the card's click said; true when it was one of these
func act(a: String) -> bool:
	flash = ""
	match a:
		"nop":
			return true
		"mprev":
			mo -= 1
			day = 0
		"mnext":
			mo += 1
			day = 0
		"mtoday":
			mo = 0
			day = 0
		"dayoff":
			day = 0
		"add_day":
			var s := shown()
			var d := today()
			if day > 0:
				d = {"y": s["y"], "m": s["m"], "d": day}
			elif mo != 0:
				d = {"y": s["y"], "m": s["m"], "d": 1}
			_add({"kinds": ["reminder"], "date": d})
		"timer_named":
			var at: float = h._now_local() + 30.0 * 60.0
			var t := Time.get_datetime_dict_from_unix_time(int(at))
			_add(
				{
					"kinds": ["reminder"],
					"text": "timer",
					"date": {"y": t["year"], "m": t["month"], "d": t["day"]},
					"time": "%02d:%02d" % [t["hour"], t["minute"]],
				}
			)
		"note_add":
			_add({"kinds": ["note"]})
		"proj_new":
			_add({"kinds": ["project"]})
		"step_add":
			_add({"kinds": ["todo"], "project": proj})
		"wait_add":
			_add({"kinds": ["waiting"]})
		"pk_done":
			h.acted.emit(int(pick["id"]), "done")
			h.close_card()
		"pk_else":
			h.acted.emit(int(pick["id"]), "else")
		"pk_not":
			h.acted.emit(int(pick["id"]), "nottoday")
		"pk_del":
			_delete(int(pick["id"]))
		_:
			return _act_arg(a)
	return true


func _act_arg(a: String) -> bool:
	var at := a.find(":")
	if at < 0:
		return false
	var what := a.substr(0, at)
	var arg := a.substr(at + 1)
	var n := int(arg)
	match what:
		"day":
			day = 0 if day == n else n
		"edit":
			edit(n)
		"timer":
			var t := Time.get_datetime_dict_from_unix_time(int(h._now_local() + n * 60.0))
			var stamp := (
				"%04d-%02d-%02dT%02d:%02d"
				% [t["year"], t["month"], t["day"], t["hour"], t["minute"]]
			)
			post.emit("/api/home/add", {"kind": "reminder", "text": "timer", "at": stamp})
		"tab":
			tab = arg
			proj = 0
			h.card.page = 0
		"proj":
			proj = n
		"note_del", "del":
			if (what == "note_del" or Sure.needs(find(n))) and not h.sure.ask(a):
				return true
			h.acted.emit(n, "delete")
		"done":
			h.acted.emit(n, "done")
		"revive":
			h.acted.emit(n, "revive")
		"up", "dn", "rm":
			_reorder(what, n)
		_:
			return false
	return true


func _delete(id: int) -> void:
	var row := find(id)
	if row.is_empty():
		row = pick
	if Sure.needs(row) and not h.sure.ask("del:%d" % id):
		return
	h.acted.emit(id, "delete")


func _reorder(what: String, i: int) -> void:
	var plan: Array = find(proj).get("plan", []).duplicate()
	if i < 0 or i >= plan.size():
		return
	match what:
		"up":
			if i == 0:
				return
			plan.insert(i - 1, plan.pop_at(i))
		"dn":
			if i == plan.size() - 1:
				return
			plan.insert(i + 1, plan.pop_at(i))
		"rm":
			plan.remove_at(i)
	post.emit("/api/home/%d/plan" % proj, {"plan": plan})
