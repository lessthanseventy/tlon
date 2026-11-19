extends RefCounted

# The soak's checks of the sidebar as a whole: every thing in the room opens a view or toggles, the
# views never lie outside the window at the smallest and the largest sizes, and a banner never takes
# a view away. Nothing here reaches a server.
const Sidebar := preload("res://sidebar.gd")
const SIZES :=[Vector2(900, 600), Vector2(1100, 700), Vector2(1920, 1080)]
const VIEWS := ["home", "item", "open", "add", "pet", "closet", "settings", "decorate", "card"]

var s
var main
var h
var sb


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home
	sb = main._sidebar


func _frames(n: int = 3) -> void:
	for _i in n:
		await s.process_frame


func run() -> void:
	await _things()
	await _fit()
	await _pet()
	await _banner()
	await _decorate_tabs()


func _centre(key: String) -> Variant:
	for hit in h._hits:
		if hit["key"] != key:
			continue
		var sum := Vector2.ZERO
		for p: Vector2 in hit["poly"]:
			sum += p
		var c: Vector2 = sum / maxf(1.0, hit["poly"].size())
		if h._topmost(c) == key:
			return c
	return null


# a click on each thing leaves the home view, or turns something on or off
func _things() -> void:
	main._at = "home"
	sb.back()
	h.decorating = false
	await _frames()
	var seen := 0
	for key in [
		"cal", "jar", "window", "clock", "plant", "board", "mousehole", "furn:fireplace",
		"furn:bookshelf", "furn:piano", "globe", "wardrobe", "pad", "stack", "phone", "tv"
	]:
		var c: Variant = _centre(key)
		if c == null:
			continue
		seen += 1
		sb.back()
		await _frames()
		var was := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		h.click(c)
		await _frames()
		var now := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		s._check(now != was, "a click on %s opens a view or toggles (%s)" % [key, str(now)])
		if key != "tv" and key != "phone":
			s._check(sb.selected_key() == h.selected, "%s stays highlighted" % key)
		sb.back()
		await _frames()
	s._check(seen >= 8, "the room has things to click: %d" % seen)
	sb.back()
	var a: Variant = _centre("cal")
	var b: Variant = _centre("jar")
	if a != null and b != null:
		h.click(a)
		await _frames()
		h.click(b)
		await _frames()
		s._check(sb.view == "card" and h.card.kind == "jar", "thing B replaces thing A's view")
		sb.back()
		await _frames()
		s._check(sb.view == "home" and h.selected == "", "back brings the home view, nothing selected")


# every control of every view sits inside the window, at the smallest and the largest size
func _fit() -> void:
	var was: Vector2 = main.size
	for size in SIZES:
		main.size = size
		var win := Rect2(Vector2.ZERO, size)
		for name in ["home", "add", "pet", "pet_edit", "closet", "settings", "card"]:
			sb.back()
			await _frames()
			match name:
				"add":
					sb.open_add(true)
				"pet":
					sb.open_pet("nina")
				"pet_edit":
					sb.open_pet("nina")
					sb.pet_view._open_edit()
				"closet":
					sb.open_closet()
				"settings":
					sb.open_settings()
				"card":
					h.card.open("calendar", "cal")
			await _frames(4)
			var out := _outside(win)
			s._check(out == "", "no %s control lies outside a %s window: %s" % [name, size, out])
			s._check(sb.get_global_rect().end.x <= size.x + 0.5, "the sidebar fits a %s window" % size)
		sb.back()
	main.size = was
	await _frames()


func _outside(win: Rect2) -> String:
	var bad: Array = []
	for c in sb.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.x < win.position.x - 0.5 or r.end.x > win.end.x + 0.5:
			bad.append("%s %s" % [c.name, r])
	return ", ".join(bad.slice(0, 3))


# a click on a pet opens its view, not the controls; Esc goes back one level at a time
func _pet() -> void:
	main._at = "home"
	sb.back()
	await _frames()
	var cat = h.pets.critter("nina")
	var c: Vector2 = h.pets.hit_rect(cat, h._o, h._k).get_center()
	if h.pet_at(c) == "nina":
		h.click(c)
	else:
		main._on_viewed("pet", "nina")
	await _frames()
	var v = sb.pet_view
	s._check(sb.view == "pet" and v.visible, "a click on a pet opens its view")
	s._check(v._page.visible and not v._tiles["cat_black"].is_visible_in_tree(), "not the kind grid")
	s._check(not sb.takes_text(), "the pets go on with their day while it is open")
	v._open_edit()
	await _frames()
	s._check(sb.takes_text() and v._tiles["cat_black"].is_visible_in_tree(), "change who this is")
	s._check(is_equal_approx(sb.size.x, Sidebar.WIDTH), "the pane stays %d wide" % Sidebar.WIDTH)
	sb.back()
	await _frames()
	s._check(sb.view == "pet" and v._page.visible and not v.editing, "Esc goes back to the pet")
	sb.back()
	await _frames()
	s._check(sb.view == "home", "and again goes home")


# a slip or a ring over an open view takes nothing from it
func _banner() -> void:
	sb.back()
	main._open_add(false)
	await _frames()
	var form_was: bool = sb.form.visible
	h.rhythm.show_slip("home", "Still open", [])
	await _frames()
	s._check(sb.view == "add" and sb.form.visible == form_was, "a slip leaves the add view be")
	h.rhythm.dismiss()
	main._open_settings()
	h.show_reply("noted")
	await _frames()
	s._check(sb.view == "settings", "a reply leaves the settings be")
	sb.back()
	await _frames()
	s._check(sb.view == "home", "and back still goes home")


# the pane is no wider than its 360 px with the decorate view up, whichever tab, and every tab shows
func _decorate_tabs() -> void:
	if not h.layout.art:
		return
	main._set_decorate(true)
	await _frames(3)
	var d = main._decorate
	for t in h.layout.tabs:
		d.tab = t
		d.queue_redraw()
		await _frames(2)
		s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the sidebar stays %d wide on %s" % [sb.WIDTH, t])
	for hit in d._hits:
		if str(hit["act"]).begins_with("tab:"):
			s._check(hit["rect"].end.x <= d.size.x - 4.0, "the %s tab fits the pane" % hit["act"])
	main._set_decorate(false)
	await _frames()
