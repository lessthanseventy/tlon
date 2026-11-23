extends RefCounted

# What the bank's arithmetic shares: dates as "YYYY-MM-DD" strings (they order and compare as
# text, and are what the routes carry), whole-day arithmetic on them, and a stable sort.
# A day count is days since 1970-01-01 in the proleptic Gregorian calendar.

const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


static func days_from_civil(y: int, m: int, d: int) -> int:
	y -= 1 if m <= 2 else 0
	var era := (y if y >= 0 else y - 399) / 400
	var yoe := y - era * 400
	var doy := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


static func civil_from_days(z: int) -> Array:
	z += 719468
	var era := (z if z >= 0 else z - 146096) / 146097
	var doe := z - era * 146097
	var yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp := (5 * doy + 2) / 153
	var d := doy - (153 * mp + 2) / 5 + 1
	var m := mp + (3 if mp < 10 else -9)
	return [y + (1 if m <= 2 else 0), m, d]


static func leap(y: int) -> bool:
	return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


static func month_days(y: int, m: int) -> int:
	if m == 2:
		return 29 if leap(y) else 28
	return 30 if m in [4, 6, 9, 11] else 31


# whether `text` is a real calendar date written YYYY-MM-DD
static func valid(text: Variant) -> bool:
	if not text is String or text.length() != 10 or text[4] != "-" or text[7] != "-":
		return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]:
		if not text[i] in "0123456789":
			return false
	var y := int(text.substr(0, 4))
	var m := int(text.substr(5, 2))
	var d := int(text.substr(8, 2))
	return m >= 1 and m <= 12 and d >= 1 and d <= month_days(y, m)


static func days(iso: String) -> int:
	return days_from_civil(int(iso.substr(0, 4)), int(iso.substr(5, 2)), int(iso.substr(8, 2)))


static func iso(day_count: int) -> String:
	var c := civil_from_days(day_count)
	return "%04d-%02d-%02d" % c


# `a` minus `b`, in days
static func diff(a: String, b: String) -> int:
	return days(a) - days(b)


static func add(iso_date: String, n: int) -> String:
	return iso(days(iso_date) + n)


# the date `n` months on, its day of the month kept or cut to the month's last day
static func shift_months(iso_date: String, n: int) -> String:
	var y := int(iso_date.substr(0, 4))
	var m := int(iso_date.substr(5, 2)) - 1 + n
	var d := int(iso_date.substr(8, 2))
	y += floori(m / 12.0)
	m = posmod(m, 12) + 1
	return "%04d-%02d-%02d" % [y, m, mini(d, month_days(y, m))]


static func shift_years(iso_date: String, n: int) -> String:
	return shift_months(iso_date, 12 * n)


static func weekday(iso_date: String) -> int:
	return posmod(days(iso_date) + 4, 7)


# "Fri"
static func day_name(iso_date: String) -> String:
	return WEEKDAYS[weekday(iso_date)]


# "Fri 5 Nov"
static func day_long(iso_date: String) -> String:
	return "%s %d %s" % [day_name(iso_date), int(iso_date.substr(8, 2)), month_name(iso_date)]


# "5 Nov"
static func day_short(iso_date: String) -> String:
	return "%d %s" % [int(iso_date.substr(8, 2)), month_name(iso_date)]


static func month_name(iso_date: String) -> String:
	return MONTHS[int(iso_date.substr(5, 2)) - 1]


# "2026-11"
static func month_key(iso_date: String) -> String:
	return iso_date.substr(0, 7)


static func month_start(iso_date: String) -> String:
	return iso_date.substr(0, 8) + "01"


static func max_date(a: String, b: String) -> String:
	return a if a >= b else b


static func min_date(a: String, b: String) -> String:
	return a if a <= b else b


# the local date of the unix time `at`, shifted by `bias` seconds from UTC
static func date_of_unix(at: float, bias: float = 0.0) -> String:
	return iso(floori((at + bias) / 86400.0))


# orders values the way a tuple sorts: numbers by value, strings by text, arrays element by
# element (the shorter first when one begins the other); -1, 0 or 1
static func compare(a: Variant, b: Variant) -> int:
	if a is Array and b is Array:
		for i in mini(a.size(), b.size()):
			var c := compare(a[i], b[i])
			if c != 0:
				return c
		return signi(a.size() - b.size())
	if a == b:
		return 0
	return -1 if a < b else 1


# `items` sorted by `key` (a Callable from an item to a comparable value), equal keys in their
# first order: Godot's own sort does not promise that
static func sort_by(items: Array, key: Callable, descending: bool = false) -> Array:
	var keyed: Array = []
	for i in items.size():
		keyed.append([key.call(items[i]), i, items[i]])
	keyed.sort_custom(
		func(a: Array, b: Array) -> bool:
			var c := compare(a[0], b[0])
			if descending:
				c = -c
			return c < 0 if c != 0 else a[1] < b[1]
	)
	return keyed.map(func(k: Array) -> Variant: return k[2])


# `items` without those whose `key` was already seen, the first of each kept
static func uniq_by(items: Array, key: Callable) -> Array:
	var seen := {}
	var out: Array = []
	for item in items:
		var k: Variant = key.call(item)
		if not seen.has(k):
			seen[k] = true
			out.append(item)
	return out


# items grouped by `key` into {key: [items]}, each list in the order given
static func group_by(items: Array, key: Callable) -> Dictionary:
	var out := {}
	for item in items:
		var k: Variant = key.call(item)
		if not out.has(k):
			out[k] = []
		out[k].append(item)
	return out


static func sum(values: Array) -> int:
	var total := 0
	for v in values:
		total += int(v)
	return total


# the dollars of `cents` as said aloud: "$1,200" for whole dollars, "$14.99" otherwise
static func money(cents: int) -> String:
	if cents < 0:
		return "-" + money(-cents)
	var whole := str(cents / 100)
	var out := ""
	while whole.length() > 3:
		out = "," + whole.substr(whole.length() - 3) + out
		whole = whole.substr(0, whole.length() - 3)
	out = whole + out
	return "$" + out if cents % 100 == 0 else "$%s.%02d" % [out, cents % 100]


# outside text as one plain line of at most `max_len` characters: control characters and runs of
# space become one space
static func line(text: Variant, max_len: int) -> String:
	if not text is String:
		return ""
	var re := RegEx.create_from_string("[\\p{C}\\s]+")
	return re.sub(text, " ", true).strip_edges().substr(0, max_len)


# a number as whole cents, rounded half away from zero (`null` for anything else)
static func cents_of(amount: Variant) -> Variant:
	if amount is int or amount is float:
		return int(roundf(float(amount) * 100.0))
	return null


# a kept account counts toward the money when it is a depository account of subtype checking
static func spendable(account: Dictionary) -> bool:
	return account.get("type") == "depository" and account.get("subtype") == "checking"


# the sum of `value` of each of `accounts`, null with none or with no value; `value` is a Callable
static func total(accounts: Array, value: Callable) -> Variant:
	var found: Array = []
	for a in accounts:
		var v: Variant = value.call(a)
		if v != null:
			found.append(int(v))
	return null if found.is_empty() else sum(found)


static func available_of(account: Dictionary) -> Variant:
	var a: Variant = account.get("available")
	return a if a != null else account.get("current")


# the available balance (else the current) of the spendable accounts, in cents; null with none
static func spendable_available(accounts: Array) -> Variant:
	return total(accounts.filter(func(a): return spendable(a)), available_of)


# the depository accounts that are not spendable (savings and the like) as {cents, names}
static func other_available(accounts: Array) -> Dictionary:
	var others := accounts.filter(
		func(a): return a.get("type") == "depository" and not spendable(a)
	)
	var names: Array = []
	for a in others:
		if a.get("name") is String and a["name"] != "":
			names.append(a["name"])
	var cents: Variant = total(others, available_of)
	return {"cents": 0 if cents == null else cents, "names": names}
