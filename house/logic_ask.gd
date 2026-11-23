extends "res://logic_local.gd"

# The logic checks of the money chat: the plan read strictly (ask_plan.gd), the results worded,
# led, checked and held against a verdict (ask_say.gd).
const Say := preload("res://ask_say.gd")
const Plan := preload("res://ask_plan.gd")

const PLAN_TODAY := "2026-11-20"


func run() -> void:
	_plan_asks()
	_plan_changes()
	_plan_match()
	_plan_cannot()
	_plan_refused()
	_plan_four_asks()
	_say_other_accounts()
	_say_summary_bills()
	_say_short_without()
	_say_drop_leads()
	_say_sentences()
	_say_contradicts()
	_say_errors()
	_say_check()
	_say_present()
	_say_budget()


func _plan_of(asks: Array) -> String:
	return JSON.stringify({"asks": asks})


func _plan_asks() -> void:
	var reply := (
		'{"asks": [{"ask": "summary"}, {"ask": "subscriptions"}, '
		+ '{"ask": "forecast", "until": "2026-12-20"}, '
		+ '{"ask": "afford", "amount_cents": 40000, "on": "2026-11-27"}]}\n'
	)
	var r := Plan.parse(reply, PLAN_TODAY)
	s._check(r.has("ok") and r["ok"].size() == 4, "four asks are read: %s" % str(r))
	if not r.has("ok") or r["ok"].size() != 4:
		return
	var summary: Dictionary = r["ok"][0]
	_eq(summary["call"], {"call": "summary"}, "summary")
	_eq(r["ok"][1]["call"], {"call": "subscriptions"}, "subscriptions")
	_eq(r["ok"][2]["call"], {"call": "forecast", "until": "2026-12-20"}, "forecast")
	var afford: Dictionary = r["ok"][3]
	_eq(afford["call"], {"call": "afford", "cents": 40000, "on": "2026-11-27"}, "afford call")
	_eq(
		afford["json"],
		{"ask": "afford", "amount_cents": 40000, "on": "2026-11-27"},
		"afford canonical json"
	)


func _plan_changes() -> void:
	var reply := _plan_of(
		[
			{
				"ask": "what_if",
				"until": "2026-12-20",
				"changes":
				[
					{
						"kind": "one_off",
						"amount_cents": 5000,
						"on": "2026-11-25",
						"name": " Dinner "
					},
					{
						"kind": "recurring",
						"amount_cents": 999,
						"rhythm": "monthly",
						"from": "2026-12-01",
						"name": "Gym"
					},
					{"kind": "drop", "name": "Rent"},
					{"kind": "change", "name": "Rent", "amount_cents": 100000},
				]
			},
			{"ask": "history", "match": "groceries", "from": "2026-08-01", "to": "2026-11-20"},
		]
	)
	var r := Plan.parse(reply, PLAN_TODAY)
	s._check(r.has("ok") and r["ok"].size() == 2, "what_if and history are read: %s" % str(r))
	if not r.has("ok") or r["ok"].size() != 2:
		return
	_eq(
		r["ok"][0]["call"],
		{
			"call": "what_if",
			"changes":
			[
				{"kind": "one_off", "cost": 5000, "on": "2026-11-25", "name": "Dinner"},
				{
					"kind": "recurring",
					"cost": 999,
					"rhythm": "monthly",
					"from": "2026-12-01",
					"name": "Gym"
				},
				{"kind": "drop", "name": "Rent"},
				{"kind": "change", "name": "Rent", "cost": 100000},
			],
			"until": "2026-12-20",
		},
		"what_if call"
	)
	_eq(
		r["ok"][1]["call"],
		{
			"call": "history",
			"query": {"match": "groceries", "from": "2026-08-01", "to": "2026-11-20"}
		},
		"history call"
	)


func _plan_history(match_value: Variant) -> String:
	return _plan_of(
		[{"ask": "history", "match": match_value, "from": "2026-08-01", "to": "2026-11-20"}]
	)


func _plan_match() -> void:
	var r := Plan.parse(_plan_history([" Whole Foods ", "Trader Joe's"]), PLAN_TODAY)
	s._check(r.has("ok"), "a list of labels is a plan")
	if r.has("ok"):
		_eq(
			r["ok"][0]["call"]["query"]["match"],
			["Whole Foods", "Trader Joe's"],
			"the labels are trimmed"
		)
		_eq(r["ok"][0]["json"]["match"], ["Whole Foods", "Trader Joe's"], "and canonical")
	r = Plan.parse(_plan_history(null), PLAN_TODAY)
	s._check(r.has("ok") and r["ok"][0]["call"]["query"]["match"] == null, "a null match is kept")
	var bad: Array = [
		[], "a".repeat(13).split(""), [""], [" "], ["x".repeat(41)], [1], ["a", null], {"a": 1}
	]
	for b in bad:
		_eq(
			Plan.parse(_plan_history(b), PLAN_TODAY),
			{"error": true},
			"match %s is no plan" % str(b)
		)
	r = Plan.parse(_plan_history("a".repeat(12).split("")), PLAN_TODAY)
	s._check(r.has("ok"), "twelve labels are allowed")


func _plan_cannot() -> void:
	_eq(
		Plan.parse('sure {"cannot": " That is not about your money. "}', PLAN_TODAY),
		{"cannot": "That is not about your money."},
		"a cannot is its sentence"
	)


func _plan_refused() -> void:
	var cases := [
		["no JSON", "I think you can afford it"],
		["unknown ask", '{"asks":[{"ask":"transfer","amount_cents":100}]}'],
		["a write-looking ask", '{"asks":[{"ask":"pay","amount_cents":100}]}'],
		["bad date", '{"asks":[{"ask":"forecast","until":"next friday"}]}'],
		["impossible date", '{"asks":[{"ask":"forecast","until":"2026-02-30"}]}'],
		["a date in the past", '{"asks":[{"ask":"forecast","until":"2026-10-01"}]}'],
		["a date years ahead", '{"asks":[{"ask":"forecast","until":"2030-01-01"}]}'],
		["a float amount", '{"asks":[{"ask":"afford","amount_cents":40.5,"on":null}]}'],
		["a string amount", '{"asks":[{"ask":"afford","amount_cents":"400","on":null}]}'],
		["a zero amount", '{"asks":[{"ask":"afford","amount_cents":0,"on":null}]}'],
		["an absurd amount", '{"asks":[{"ask":"afford","amount_cents":100000001,"on":null}]}'],
		["a missing amount", '{"asks":[{"ask":"afford"}]}'],
		["no asks", '{"asks":[]}'],
		["an empty cannot", '{"cannot":"  "}'],
		[
			"a history backwards",
			'{"asks":[{"ask":"history","match":null,"from":"2026-11-20","to":"2026-10-01"}]}'
		],
		[
			"a what_if with no changes",
			'{"asks":[{"ask":"what_if","until":"2026-12-20","changes":[]}]}'
		],
		[
			"an unknown change",
			'{"asks":[{"ask":"what_if","until":"2026-12-20","changes":[{"kind":"zap"}]}]}'
		],
		[
			"an unknown rhythm",
			(
				'{"asks":[{"ask":"what_if","until":"2026-12-20","changes":[{"kind":"recurring",'
				+ '"amount_cents":5,"rhythm":"daily","from":"2026-12-01","name":"x"}]}]}'
			)
		],
		[
			"a nameless drop",
			'{"asks":[{"ask":"what_if","until":"2026-12-20","changes":[{"kind":"drop","name":""}]}]}'
		],
		[
			"five asks",
			_plan_of(
				[
					{"ask": "summary"},
					{"ask": "summary"},
					{"ask": "summary"},
					{"ask": "summary"},
					{"ask": "summary"}
				]
			)
		],
		["one bad ask among good", '{"asks":[{"ask":"summary"},{"ask":"forecast"}]}'],
	]
	for c in cases:
		_eq(Plan.parse(c[1], PLAN_TODAY), {"error": true}, "%s is no plan" % c[0])


func _plan_four_asks() -> void:
	var r := Plan.parse(
		_plan_of([{"ask": "summary"}, {"ask": "summary"}, {"ask": "summary"}, {"ask": "summary"}]),
		PLAN_TODAY
	)
	s._check(r.has("ok") and r["ok"].size() == 4, "four asks are allowed")


func _say_other_accounts() -> void:
	var result := func(covered: bool) -> Array:
		return [
			{
				"ask": {"ask": "afford", "amount_cents_text": "$400", "on": null},
				"result":
				{
					"verdict": "short",
					"shortfall_cents_text": "$120.00",
					"short_on": "2026-11-27",
					"other_available_cents": 90000,
					"other_available_cents_text": "$900",
					"other_accounts": ["Acme Savings"],
					"covered_by_other": covered,
					"with": {"lowest": {}},
				},
			}
		]
	_eq(
		Say.leads(result.call(true)),
		[
			"A purchase of $400 on today would leave you short by $120.00 on Fri 27 Nov. This is checking alone; Acme Savings holds $900, which covers it."
		],
		"the lead says the other accounts cover a shortfall"
	)
	var leads := Say.leads(result.call(false))
	s._check(leads.size() == 1, "one lead")
	s._check(leads[0].ends_with("which does not cover it."), "or that they do not: %s" % leads[0])


func _say_summary_bills() -> void:
	var item := func(name: String, on: String) -> Dictionary:
		return {"name": name, "amount_cents_text": "$10", "on": on}
	var presented := [
		{
			"ask": {"ask": "summary"},
			"result":
			{
				"available_cents_text": "$500",
				"due_this_week":
				[
					item.call("Early", "2026-11-26"),
					item.call("Same", "2026-11-27"),
					item.call("Late", "2026-11-28")
				],
				"next_deposit": item.call("Pay", "2026-11-27"),
			}
		}
	]
	var text := Say.render(presented)
	s._check("Early $10 Thu 26 Nov (before the next deposit)" in text, "before: %s" % text)
	s._check(
		"Same $10 Fri 27 Nov (the same day as the next deposit)" in text, "same day: %s" % text
	)
	s._check("Late $10 Sat 28 Nov (after the next deposit)" in text, "after: %s" % text)
	var no_deposit: Array = presented.duplicate(true)
	no_deposit[0]["result"]["next_deposit"] = null
	s._check(not "next deposit)" in Say.render(no_deposit), "with no deposit none is placed")


func _say_short_without() -> void:
	var presented := [
		{
			"ask": {"ask": "afford", "amount_cents_text": "$50.00", "on": null},
			"result":
			{
				"verdict": "short",
				"short_without": true,
				"baseline_shortfall_cents_text": "$120.00",
				"baseline_short_on": "2026-11-27",
				"adds_cents": 5000,
				"adds_cents_text": "$50.00",
				"with": {"lowest": {}},
			}
		}
	]
	_eq(
		Say.leads(presented),
		[
			"Without it your balance is already projected short by $120.00 on Fri 27 Nov. A purchase of $50.00 on today would deepen it by $50.00."
		],
		"the lead names a baseline that is already short and what the purchase adds"
	)


func _say_drop_leads() -> void:
	var lead := "A purchase of $400 on today is covered: your lowest expected balance would be $1,000 on Fri 27 Nov."
	var tail := " It rests on your history."
	for restated in [lead, lead.to_lower(), lead.replace(" ", "  "), lead.trim_suffix(".")]:
		_eq(
			Say.drop_leads(restated + tail, [lead]),
			"It rests on your history.",
			"a restated lead is dropped: %s" % restated
		)
	_eq(Say.drop_leads(lead, [lead]), "", "a text that is the lead alone is empty")


func _say_sentences() -> void:
	var rant := [
		{
			"ask": {"ask": "what_if", "changes": [{"kind": "drop", "name": "Rant"}]},
			"result": {"error": "no_series", "name": "Rant", "suggestions": ["Rent"]},
		}
	]
	_eq(
		Say.leads(rant),
		['I don\'t see a recurring charge called "Rant". Did you mean Rent?'],
		"a series not found is code's sentence"
	)
	_eq(
		Say.facts(rant),
		[{"about": "a series that was not found", "name": "Rant", "suggestions": ["Rent"]}],
		"and a fact for the judge"
	)
	var far := [
		{
			"ask": {"ask": "afford", "amount_cents": 40000, "on": "2026-09-16"},
			"result": {"error": "beyond_horizon"},
		}
	]
	_eq(
		Say.leads(far),
		["I can only look 180 days ahead, so I can't say for Wed 16 Sep."],
		"a date past the horizon is code's sentence"
	)
	var trip := [
		{
			"ask":
			{
				"ask": "what_if",
				"until": "2026-09-16",
				"changes": [{"kind": "one_off", "on": "2026-09-16", "name": "Trip"}]
			},
			"result": {"error": "beyond_horizon"},
		}
	]
	_eq(
		Say.leads(trip),
		["I can only look 180 days ahead, so I can't say for Wed 16 Sep."],
		"a what_if's latest change date"
	)
	_eq(Say.facts(far), [], "a date past the horizon has no fact for the judge")
	s._check(Say.only_beyond_horizon(far), "only beyond the horizon")
	s._check(not Say.only_beyond_horizon(far + rant), "not beside a real result")
	s._check(not Say.only_beyond_horizon([]), "nothing is not beyond the horizon")


func _verdict(verdict: String) -> Array:
	return [{"ask": {"ask": "afford"}, "result": {"verdict": verdict}}]


func _say_contradicts() -> void:
	for text in [
		"You can afford it.",
		"It should be fine.",
		"Go for it!",
		"There is plenty left.",
		"You'd manage comfortably.",
		"No issue here.",
		"NO PROBLEM",
	]:
		s._check(Say.contradicts(text, _verdict("short")), "affirms a short verdict: %s" % text)
	s._check(
		not Say.contradicts("It rests on your history.", _verdict("short")),
		"history is no affirmation"
	)
	s._check(
		not Say.contradicts("Plentyful is not a word here.", _verdict("short")),
		"plentyful is not plenty"
	)
	for text in [
		"You can't afford it.",
		"You cannot afford it.",
		"It is not fine, you won't afford it.",
	]:
		s._check(not Say.contradicts(text, _verdict("short")), "a negated affirmation: %s" % text)
	for verdict in ["covers", "tight"]:
		for text in [
			"You cannot do this.",
			"You won't be able to pay.",
			"You'd fall short.",
			"It would overdraw you.",
			"Your balance goes negative.",
			"You don't have enough.",
			"Better hold off.",
		]:
			s._check(Say.contradicts(text, _verdict(verdict)), "denies %s: %s" % [verdict, text])
	s._check(
		not Say.contradicts("You are not short on that day.", _verdict("covers")),
		"not short is no denial"
	)
	s._check(
		not Say.contradicts("It isn't negative at any point.", _verdict("tight")),
		"not negative is no denial"
	)


func _say_errors() -> void:
	var entry := {
		"ask": {"ask": "afford", "amount_cents": 0, "on": null}, "result": {"error": "bad_amount"}
	}
	var presented := Say.present([entry])
	_eq(presented[0]["result"], {"error": "bad_amount"}, "bad_amount is a result")
	s._check("can't be worked out" in Say.render(presented), "and is worded")
	entry = {
		"ask": {"ask": "history", "match": null, "from": "2026-11-20", "to": "2026-10-01"},
		"result": {"error": "bad_range"},
	}
	presented = Say.present([entry])
	_eq(presented[0]["result"], {"error": "bad_range"}, "bad_range is a result")
	s._check("runs backwards" in Say.render(presented), "and is worded")


func _say_budget() -> void:
	var r := Plan.parse('{"asks": [{"ask": "budget"}]}', PLAN_TODAY)
	_eq(r.get("ok", [{}])[0].get("call"), {"call": "budget"}, "a budget is asked for")
	var week := func(from: String, total: int, top: Array) -> Dictionary:
		return {"from": from, "to": from, "total_cents": total, "top": top}
	var budget := {
		"until": "2026-11-27",
		"deposit": "Paycheck",
		"days": 4,
		"bills_cents": 12000,
		"bills": [],
		"cushion_cents": 3000,
		"safe_daily_cents": 4500,
		"short_cents": 0,
		"spent_today_cents": 2300,
		"weeks":
		[
			week.call("2026-11-23", 14000, [{"name": "Walmart", "amount_cents": 14000}]),
			week.call("2026-11-16", 0, []),
		],
		"other_available_cents": 0,
		"other_accounts": [],
	}
	var presented := Say.present([{"ask": {"ask": "budget"}, "result": {"ok": budget}}])
	var text := Say.render(presented)
	_eq(
		text,
		(
			"You can spend about $45 a day until the next deposit (Paycheck, Fri 27 Nov),"
			+ " after $120 of bills before it and a $30 cushion. Spent today: $23."
			+ " This week: $140 in all, most at Walmart $140. Last week: $0 in all."
		),
		"the budget in plain words"
	)
	_eq(
		Say.check("Keep to about $45 a day; Walmart took $140 this week.", presented),
		{"ok": true},
		"a model's advice may use its figures"
	)
	var short: Dictionary = budget.duplicate(true)
	short["safe_daily_cents"] = 0
	short["short_cents"] = 8000
	_eq(
		(
			Say
			. render(Say.present([{"ask": {"ask": "budget"}, "result": {"ok": short}}]))
			. begins_with(
				"Nothing is spare until the next deposit (Paycheck, Fri 27 Nov): you are about $80 short"
			)
		),
		true,
		"nothing spare, plainly"
	)


func _say_check() -> void:
	var presented := [
		{"result": {"a_text": "$1,200", "b_text": "-$14.99", "c": {"d_text": "$0.50"}}}
	]
	_eq(
		Say.check(
			"Rent is $1,200, or $1200.00; the charge is $14.99; later $0.50 and $0.", presented
		),
		{"ok": true},
		"amounts equal to a result's, however written, pass"
	)
	_eq(Say.check("1,200 dollars out", presented), {"ok": true}, "dollars in words")
	_eq(Say.check("no money words at all, 3 days, 40%", presented), {"ok": true}, "no amounts")
	for c in [
		["Rent is $1,201.", "$1,201"],
		["about $1.2k", "$1.2k"],
		["$14.999", "$14.999"],
		["500 dollars", "500 dollars"],
	]:
		_eq(Say.check(c[0], presented), {"error": [c[1]]}, "%s is missing" % c[0])


func _say_present() -> void:
	var events: Array = []
	for i in 50:
		events.append({"on": "2026-11-21", "n": i})
	var forecast := {
		"start_cents": 1500,
		"until": "2026-12-20",
		"clamped": true,
		"days": [{"date": "2026-11-21"}, {"date": "2026-11-22"}],
		"events": events,
	}
	var entries := [{"ask": {"ask": "forecast", "until": "2026-12-20"}, "result": {"ok": forecast}}]
	var r: Dictionary = Say.present(entries)[0]["result"]
	_eq(r["start_cents_text"], "$15", "a *_cents gets its dollars beside it")
	_eq(r["end"], {"date": "2026-11-22"}, "the days become the last one")
	_eq(r["events"].size(), 40, "the events are cut to forty")
	s._check(not r.has("days"), "the days are dropped")
	s._check(
		r["note"].begins_with("The horizon was cut to 180 days"),
		"a clamped forecast says so: %s" % r
	)
	_eq(forecast["days"].size(), 2, "the engine's result is not changed")
	_eq(forecast["events"].size(), 50, "nor its events")
