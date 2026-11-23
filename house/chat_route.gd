extends RefCounted

# What a line typed to the chat is, decided by code and never by a model: the settling of an item of
# Your move in words, a question about the money, a question about the list, or else a tell for the
# reader as before. Pure functions over the line and the open items.
const MONEY := [
	"money",
	"rent",
	"bank",
	"balance",
	"afford",
	"spend",
	"spent",
	"spending",
	"bill",
	"bills",
	"subscription",
	"subscriptions",
	"savings",
	"checking",
	"paycheck",
	"deposit",
	"charge",
	"charges",
	"cash",
	"budget",
	"owe",
	"paid",
	"salary",
	"$",
]
const ASKING := [
	"what",
	"how",
	"when",
	"which",
	"who",
	"where",
	"why",
	"do",
	"does",
	"did",
	"can",
	"could",
	"am",
	"is",
	"are",
	"will",
	"should",
	"would",
	"have",
	"has",
]
const LISTED := [
	"left",
	"open",
	"due",
	"coming",
	"plate",
	"to do",
	"todo",
	"to-do",
	"this week",
	"next week",
	"today",
	"tomorrow",
	"on my list",
	"waiting",
	"overdue",
	"agenda",
]
const GO := ["go", "yes", "yep", "ok", "okay", "do it", "looks good", "go ahead"]
const NO := ["no", "nope", "drop it", "skip it", "no thanks"]


static func _clean(line: String) -> String:
	var s := line.strip_edges().to_lower()
	while s != "" and s[-1] in [".", "!", "?", ","]:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges()


static func _has(words: Array, s: String) -> bool:
	for w in words:
		if w == "$":
			if "$" in s:
				return true
		elif RegEx.create_from_string("\\b" + w + "\\b").search(s) != null:
			return true
	return false


# a question: a question mark, or a line that opens with a question word
static func question(line: String) -> bool:
	var s := line.strip_edges().to_lower()
	return s.ends_with("?") or (s != "" and s.get_slice(" ", 0).get_slice("'", 0) in ASKING)


# "money" or "list" for a question about either, "" for any other line
static func asks(line: String) -> String:
	if not question(line):
		return ""
	var s := line.to_lower()
	if _has(MONEY, s):
		return "money"
	return "list" if _has(LISTED, s) else ""


# `{key, choice}` when `line` settles an item: a bare go, no or option number settles `shown`
# (the item said last), "no to the Spotify one" the one open proposal whose text has "Spotify";
# {} when it settles nothing, and then it is a tell as before
static func settle(line: String, shown: Dictionary, open: Array) -> Dictionary:
	var s := _clean(line)
	if s == "":
		return {}
	var named := RegEx.create_from_string("^(go|yes|no)(?: (?:to|for|on))? the (.+?)(?: one)?$")
	var hit := named.search(s)
	if hit != null:
		var found: Array = open.filter(
			func(m: Dictionary) -> bool:
				return m["kind"] != "ask" and hit.get_string(2) in str(m["text"]).to_lower()
		)
		if found.size() == 1:
			return {"key": found[0]["key"], "choice": "no" if hit.get_string(1) == "no" else "go"}
		return {}
	if shown.is_empty():
		return {}
	if shown["kind"] == "ask":
		var options: Array = shown["options"]
		if s.is_valid_int() and int(s) >= 1 and int(s) <= options.size():
			return {"key": shown["key"], "choice": int(s)}
		return {}
	if s in GO:
		return {"key": shown["key"], "choice": "go"}
	if s in NO:
		return {"key": shown["key"], "choice": "no"}
	return {}
