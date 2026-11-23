extends "res://soak_sidebar.gd"

# The soak's checks of Your move on screen: Home's first section, the header's count, the view with
# its keys, and what a go, a no and an answer post. The items are fixtures served by the stub.


func run() -> void:
	var keep: Dictionary = s._state.duplicate(true)
	s.seed(keep["open"], keep["coming"], {"moves": _fixtures()})
	await _poll_home()
	sb.back()
	await _sync()
	await _home()
	await _header()
	await _view()
	await _keys()
	await _clicks()
	await _empty()
	s.seed(keep["open"], keep["coming"], {"moves": []})
	await _poll_home()


func _fixtures() -> Array:
	var rem := {"do": "add", "kind": "reminder", "text": "move $120", "at": "2026-11-19T18:00"}
	return [
		{
			"key": "ask",
			"kind": "ask",
			"source": "money",
			"text": "Spotify is $13.99 now",
			"why": "was $11.99",
			"options": ["keep", "remind me to cancel", "not a bill"],
			"at": "2026-11-18T09:00:00"
		},
		{
			"key": "p1",
			"kind": "proposal",
			"source": "money",
			"text": "Move $120 from savings",
			"why": "rent is due Fri",
			"action": rem,
			"date": "2026-11-19",
			"at": "2026-11-18T09:00:01"
		},
		{
			"key": "p2",
			"kind": "proposal",
			"source": "list",
			"text": "Nudge Sam",
			"why": "waiting since Tue",
			"action": {"do": "add", "kind": "todo", "text": "nudge Sam"},
			"date": "2026-11-20",
			"at": "2026-11-18T09:00:02"
		},
		{
			"key": "p3",
			"kind": "proposal",
			"source": "list",
			"text": "Renew passport on someday",
			"why": "open since 3 Nov",
			"action": {"do": "someday", "id": 1},
			"date": "2026-11-21",
			"at": "2026-11-18T09:00:03"
		},
		{
			"key": "look",
			"kind": "look_at",
			"source": "money",
			"text": "This week's money",
			"why": "opens Money",
			"action": {"do": "open", "url": "https://example.com"},
			"date": "2026-11-22",
			"at": "2026-11-18T09:00:04"
		},
	]


func _body(l: Array) -> Dictionary:
	return l[2] if l[2] is Dictionary else JSON.parse_string(str(l[2]))


func _moves_posted() -> Array:
	return _posted("/api/home/moves/settle").map(
		func(l: Array) -> Array: return [_body(l)["key"], _whole(_body(l)["choice"])]
	)


func _home() -> void:
	var texts: Array = _texts(sb._dyn)
	s._check(texts.find("Your move (5)") == 0, "Home leads with Your move (5): %s" % str(texts))
	s._check(
		"Spotify is $13.99 now" in texts and "was $11.99" in texts, "the ask is first, with its why"
	)
	var three: bool = "Nudge Sam" in texts and not "Renew passport on someday" in texts
	s._check(three and "2 more..." in texts, "three are shown, then 2 more...: %s" % str(texts))
	s._check(_row(sb._dyn, "Spotify is $13.99 now") != null, "the ask has its row")
	s._check(_find_button(sb._dyn, "2 remind me to cancel") != null, "an ask's options are buttons")
	s._check(_mark("Move $120 from savings", "go") != null, "a proposal has go")
	s._check(_mark("Move $120 from savings", "no") != null, "a proposal has no")
	s._check(not ("Proposed" in " ".join(texts)), "no Proposed section over the list")
	await _press("2 more...")
	s._check("This week's money" in _texts(sb._dyn), "2 more... shows the rest in place")
	s._check(_mark("This week's money", "looks good") != null, "a look-at has looks good")
	await _press("less")


func _header() -> void:
	s._check(sb._needs.visible and sb._needs.count == 5, "the header counts 5")
	sb.open_add()
	await _sync()
	s._check(sb._needs.visible, "the count is in every view")
	sb.back()
	await _sync()
	sb._needs.pressed.emit()
	await _sync()
	s._check(
		sb.view == "moves" and sb.view_title() == "Your move",
		"a click on the count opens Your move"
	)


func _view() -> void:
	var texts: Array = _texts(sb._dyn)
	var at := func(t: String) -> int: return texts.find(t)
	s._check(
		at.call("Asks") < at.call("Proposals") and at.call("Proposals") < at.call("Look at"),
		"Asks, Proposals, Look at: %s" % str(texts)
	)
	s._check(
		"-> a reminder Thu 18:00" in " ".join(texts.map(func(t): return str(t).replace("\n", " "))),
		"a proposal says what go does"
	)
	s._check(
		"-> a to-do" in " ".join(texts.map(func(t): return str(t).replace("\n", " "))),
		"a to-do too"
	)
	s._check(
		texts.any(func(t): return "j k pick" in str(t) and "esc back" in str(t)),
		"the keys are written at the foot"
	)
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the pane stays %d wide" % sb.WIDTH)


func _keys() -> void:
	s._check(sb.move_pick == 0, "the first item is picked")
	s._check(sb.move_key(KEY_ENTER), "enter on an ask is taken")
	s._check(_moves_posted().is_empty(), "and settles nothing")
	sb.move_key(KEY_J)
	s._check(sb.move_pick == 1, "j picks the next")
	sb.move_key(KEY_K)
	sb.move_key(KEY_K)
	s._check(sb.move_pick == 0, "k picks the one before, and stops at the first")
	sb.move_key(KEY_2)
	await s._until(func(): return _moves_posted().size() == 1, "a digit answers the picked ask")
	s._check(
		_moves_posted()[0] == ["ask", 2], "option 2 posts the ask's key: %s" % str(_moves_posted())
	)
	sb.move_key(KEY_2)
	await _sync()
	s._check(_moves_posted().size() == 1, "a second press before the refresh posts nothing")
	await _poll_home()
	await _sync()
	s._check(sb.view == "moves" and sb._needs.count == 4, "the ask is gone, 4 are left")
	sb.move_key(KEY_ENTER)
	await s._until(func(): return _moves_posted().size() == 2, "enter is go")
	s._check(
		_moves_posted()[1] == ["p1", "go"], "go posts the proposal's key: %s" % str(_moves_posted())
	)
	await _poll_home()
	await _sync()
	sb.move_key(KEY_X)
	await s._until(func(): return _moves_posted().size() == 3, "x is no")
	s._check(_moves_posted()[2] == ["p2", "no"], "no posts the next: %s" % str(_moves_posted()))
	await _poll_home()
	await _sync()


func _clicks() -> void:
	var go: Variant = _mark("Renew passport on someday", "go")
	s._check(go != null, "the view's row has go")
	if go != null:
		go.pressed.emit()
	await s._until(func(): return _moves_posted().size() == 4, "a click on go posts")
	s._check(_moves_posted()[3] == ["p3", "go"], "the click's key: %s" % str(_moves_posted()))
	await _poll_home()
	await _sync()
	var looks: Variant = _mark("This week's money", "looks good")
	s._check(looks != null, "a look-at has looks good")
	if looks != null:
		looks.pressed.emit()
	await s._until(func(): return _moves_posted().size() == 5, "looks good posts go")
	await _poll_home()
	await _sync()


func _empty() -> void:
	var texts: Array = _texts(sb._dyn)
	s._check("nothing needs you" in texts, "an empty view says nothing needs you: %s" % str(texts))
	s._check(not sb._needs.visible, "no count at zero")
	sb.back()
	await _sync()
	texts = _texts(sb._dyn)
	s._check(
		not texts.any(func(t): return str(t).begins_with("Your move")),
		"Home draws no section at zero"
	)


func _whole(v: Variant) -> Variant:
	return int(v) if v is float else v
