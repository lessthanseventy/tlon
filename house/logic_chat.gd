extends "res://logic_local.gd"

# The logic checks of the chat as the orchestrator: which line is a settle, a money question, a list
# question or a tell (`chat_route.gd`), the list's answer (`chat_list.gd`) and how the chat says an
# item once and marks it settled (`chat.gd`). Fixtures only.
const ChatRoute := preload("res://chat_route.gd")
const ChatList := preload("res://chat_list.gd")
const Chat := preload("res://chat.gd")


func run() -> void:
	t = at(2026, 11, 18, 10)
	_asks()
	_settles()
	_finishes()
	_list_answer()
	_said()


func _p(key: String, text: String, kind: String = "proposal") -> Dictionary:
	return {
		"key": key,
		"kind": kind,
		"text": text,
		"action": {"do": "someday", "id": 1},
		"options": ["keep", "cancel", "not a bill"]
	}


func _asks() -> void:
	for line in [
		"how am i doing on rent?",
		"can I afford a chair",
		"what's my balance",
		"How much did I spend on food?"
	]:
		_eq(ChatRoute.asks(line), "money", "a money question: " + line)
	for line in ["what's left this week?", "what do I have tomorrow", "is anything due today?"]:
		_eq(ChatRoute.asks(line), "list", "a list question: " + line)
	for line in [
		"buy milk", "remind me to pay rent tomorrow", "what time is it?", "rent is due", ""
	]:
		_eq(ChatRoute.asks(line), "", "a tell: " + line)


func _settles() -> void:
	var spotify := _p("spotify", "Cancel the Spotify one")
	var ask := _p("flex", "Is Flex rent?", "ask")
	var open := [spotify, ask, _p("sam", "Nudge Sam about the invoice")]
	_eq(
		ChatRoute.settle("go", spotify, open),
		{"key": "spotify", "choice": "go"},
		"go settles the item shown"
	)
	_eq(
		ChatRoute.settle("No.", spotify, open),
		{"key": "spotify", "choice": "no"},
		"no settles it, punctuation or not"
	)
	_eq(ChatRoute.settle("looks good", spotify, open)["choice"], "go", "looks good is go")
	_eq(ChatRoute.settle("go", {}, open), {}, "go with nothing shown is a tell")
	_eq(ChatRoute.settle("go", ask, open), {}, "go does not answer an ask")
	_eq(
		ChatRoute.settle("2", ask, open),
		{"key": "flex", "choice": 2},
		"a number answers the ask shown"
	)
	_eq(ChatRoute.settle("4", ask, open), {}, "a number past the options is a tell")
	_eq(ChatRoute.settle("2", spotify, open), {}, "a number does not settle a proposal")
	_eq(
		ChatRoute.settle("no to the Sam one", ask, open),
		{"key": "sam", "choice": "no"},
		"no to the one named settles that one, whatever was shown"
	)
	_eq(
		ChatRoute.settle("go for the nobody one", spotify, open),
		{},
		"a name matching no item is a tell"
	)
	_eq(ChatRoute.settle("go home and rest", spotify, open), {}, "any other line is a tell")


func _nudge(key: String, about: String) -> Dictionary:
	var m := _p(key, "Nudge Sam about " + about)
	m["waiting_id"] = int(key.trim_prefix("waiting-"))
	m["about"] = about
	return m


func _finishes() -> void:
	var support := _nudge("waiting-27", "[FTC-7189] Make the support skill enumerate every record")
	var open := [support, _nudge("waiting-3", "the invoice"), _p("spotify", "Cancel Spotify")]
	for line in ["The support skill merged", "done", "it merged.", "they replied"]:
		_eq(
			ChatRoute.finished(line, support, open),
			{"key": "waiting-27", "sure": true},
			"done to the nudge shown: " + line
		)
	_eq(
		ChatRoute.finished("the support skill is in review", support, open),
		{"key": "waiting-27", "sure": false},
		"the item's own words with no done word is asked about"
	)
	_eq(
		ChatRoute.finished("i think so", support, open),
		{"key": "waiting-27", "sure": false},
		"a vague reply is asked about"
	)
	for line in ["buy milk", "go", "no", "what's left?", "the support skill has not merged"]:
		_eq(ChatRoute.finished(line, support, open), {}, "not a done-reply: " + line)
	_eq(ChatRoute.finished("done", {}, open), {}, "a bare done with nothing shown is a tell")
	_eq(
		ChatRoute.finished("the invoice was paid and done", {}, open),
		{"key": "waiting-3", "sure": true},
		"a done word naming exactly one nudge settles it with none shown"
	)
	_eq(
		ChatRoute.finished("the support skill merged", _p("spotify", "Cancel Spotify"), open),
		{"key": "waiting-27", "sure": true},
		"and a nudge named in the line wins over another item shown"
	)


func _list_answer() -> void:
	var l := _list()
	_eq(
		ChatList.plain(ChatList.facts(l)), "Nothing is open and nothing is coming.", "an empty list"
	)
	l.add({"kind": "todo", "text": "Fix the bike light"})
	l.add({"kind": "reminder", "text": "Call the dentist", "at": "2026-11-19T14:00"})
	l.add({"kind": "reminder", "text": "Far away", "at": "2026-12-30T14:00"})
	l.add({"kind": "waiting", "text": "the invoice", "who": "Sam"})
	var f := ChatList.facts(l)
	_eq(f["coming"].map(func(r): return r["text"]), ["Call the dentist"], "only the next 7 days")
	_eq(f["coming"][0]["when"], "tomorrow 14:00", "worded by the time rule")
	_eq(
		ChatList.plain(f),
		"Coming up in the next 7 days: Call the dentist (tomorrow 14:00). Open: Fix the bike light. Waiting on: Sam: the invoice.",
		"the plain answer"
	)
	s._check(
		"Call the dentist" in ChatList.prompt("what's left?", f), "the prompt carries the facts"
	)


func _said() -> void:
	var c := Chat.new()
	c.setup(false)
	var open := [_p("a", "Move $120"), _p("flex", "Is Flex rent?", "ask")]
	c.sync_moves(open, {})
	_eq(c.messages.size(), 2, "each open item is said")
	c.sync_moves(open, {})
	_eq(c.messages.size(), 2, "and only once")
	_eq(c.messages[0]["buttons"], [["go", "go"], ["no", "no"]], "a proposal has go and no")
	_eq(c.messages[1]["buttons"], [["1", 1], ["2", 2], ["3", 3]], "an ask has its numbers")
	s._check(
		"1 keep · 2 cancel · 3 not a bill" in c.messages[1]["text"], "the options are written out"
	)
	_eq(c.last_move(), "flex", "the item said last is the one a bare word settles")
	c.sync_moves([open[0]], {"flex": "answer"})
	_eq(c.messages[1]["done"], "answer", "an item settled is marked how")
	_eq(c.last_move(), "a", "and the one said last that still waits is next")
	c.sync_moves([], {})
	_eq(c.messages[0]["done"], "gone", "an item whose cause went is marked gone")
	_eq(c.last_move(), "", "nothing waits")
