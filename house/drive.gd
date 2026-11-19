extends Node

# `--drive [PORT]`: the live house driven over TCP on 127.0.0.1, one JSON object per line in and
# one out, handled between frames. Input goes through Input.parse_input_event, so the house's own
# _input/_gui_input paths run as for a person. Prints `DRIVE <port>` when listening.
const SAID_KEPT := 20
const NAMED := {
	"escape": KEY_ESCAPE,
	"enter": KEY_ENTER,
	"return": KEY_ENTER,
	"tab": KEY_TAB,
	"backspace": KEY_BACKSPACE,
	"delete": KEY_DELETE,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"up": KEY_UP,
	"down": KEY_DOWN,
	"space": KEY_SPACE,
	"home": KEY_HOME,
	"end": KEY_END,
	"pageup": KEY_PAGEUP,
	"pagedown": KEY_PAGEDOWN,
}
const BUTTONS := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
}

var _main: Control
var _home
var _srv := TCPServer.new()
var _conns: Array = []
var _busy := false
var _mouse := Vector2.ZERO
var _mask := 0
var _said: Array = []


func start(main: Control, port: int) -> int:
	_main = main
	Input.use_accumulated_input = false
	_home = main._room.home
	var chained: Callable = _home.pets.on_say
	_home.pets.on_say = func(id: String, text: String) -> void:
		_said.append("%s: %s" % [id, text])
		if _said.size() > SAID_KEPT:
			_said.pop_front()
		if chained.is_valid():
			chained.call(id, text)
	if _srv.listen(port, "127.0.0.1") != OK:
		push_error("drive: cannot listen on 127.0.0.1:%d" % port)
		return -1
	print("DRIVE %d" % _srv.get_local_port())
	return _srv.get_local_port()


func port() -> int:
	return _srv.get_local_port()


func _process(_dt: float) -> void:
	if _busy:
		return
	while _srv.is_connection_available():
		_conns.append({"peer": _srv.take_connection(), "buf": PackedByteArray()})
	for conn in _conns.duplicate():
		var peer: StreamPeerTCP = conn["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(conn)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			conn["buf"].append_array(peer.get_data(n)[1])
		var nl: int = conn["buf"].find(10)
		if nl >= 0:
			var line: String = conn["buf"].slice(0, nl).get_string_from_utf8()
			conn["buf"] = conn["buf"].slice(nl + 1)
			_serve(peer, line)
			return


func _serve(peer: StreamPeerTCP, line: String) -> void:
	_busy = true
	var parser := JSON.new()
	var cmd: Variant = parser.data if parser.parse(line) == OK else null
	var reply: Variant = null
	if cmd is Dictionary and cmd.get("do") is String:
		reply = await _do(cmd)
	else:
		reply = _fail('a command is a JSON object with a "do" string')
	if not reply is Dictionary:
		reply = _fail("the command could not be run: %s" % line.left(120))
	peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())
	_busy = false
	if cmd is Dictionary and cmd.get("do") == "quit":
		get_tree().quit()


func _fail(why: String) -> Dictionary:
	return {"ok": false, "error": why}


func _ok(extra: Dictionary = {}) -> Dictionary:
	return {"ok": true}.merged(extra)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _do(cmd: Dictionary) -> Variant:
	var verbs := {
		"move": _move,
		"click": _click,
		"down": _hold,
		"up": _hold,
		"drag": _drag,
		"wheel": _wheel,
		"key": _key,
		"type": _type,
		"wait": _wait,
		"frames": _count,
		"shot": _shot,
		"resize": _resize,
		"at": _under,
		"things": _things,
		"state": _state,
		"set": _levers,
		"quit": _quit,
	}
	if not verbs.has(cmd["do"]):
		return _fail("unknown command: %s" % cmd["do"])
	return await verbs[cmd["do"]].call(cmd)


func _quit(_cmd: Dictionary) -> Dictionary:
	return _ok()


func _move(cmd: Dictionary) -> Dictionary:
	var at: Variant = _at_of(cmd)
	if at == null:
		return _fail("move needs x and y")
	_motion(at)
	await _frames(2)
	return _ok()


func _hold(cmd: Dictionary) -> Dictionary:
	var at: Variant = _at_of(cmd)
	var button: Variant = BUTTONS.get(str(cmd.get("button", "left")))
	if at == null or button == null:
		return _fail("%s needs x, y and a button of left, right or middle" % cmd["do"])
	_motion(at)
	_press(at, button, cmd["do"] == "down")
	await _frames(2)
	return _ok()


func _wheel(cmd: Dictionary) -> Dictionary:
	var at: Variant = _at_of(cmd)
	if at == null or not cmd.get("dy") is float:
		return _fail("wheel needs x, y and dy")
	_motion(at)
	var notch := MOUSE_BUTTON_WHEEL_UP if float(cmd["dy"]) < 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	for _i in maxi(1, int(absf(float(cmd["dy"])))):
		_press(at, notch, true)
		_press(at, notch, false)
		await _frames(1)
	await _frames(1)
	return _ok()


func _type(cmd: Dictionary) -> Dictionary:
	if not cmd.get("text") is String:
		return _fail("type needs text")
	for ch: String in cmd["text"]:
		var code: int = ch.to_upper().unicode_at(0)
		var shift := ch != ch.to_lower()
		Input.parse_input_event(_key_event(code if code < 128 else 0, true, ch, shift))
		Input.parse_input_event(_key_event(code if code < 128 else 0, false, ch, shift))
		await _frames(1)
	await _frames(1)
	return _ok()


func _wait(cmd: Dictionary) -> Dictionary:
	if not cmd.get("seconds") is float:
		return _fail("wait needs seconds")
	await get_tree().create_timer(clampf(float(cmd["seconds"]), 0.0, 300.0)).timeout
	return _ok()


func _count(cmd: Dictionary) -> Dictionary:
	if not cmd.get("n") is float:
		return _fail("frames needs n")
	await _frames(clampi(int(cmd["n"]), 0, 6000))
	return _ok()


func _resize(cmd: Dictionary) -> Dictionary:
	if not (cmd.get("w") is float and cmd.get("h") is float):
		return _fail("resize needs w and h")
	get_window().size = Vector2i(clampi(int(cmd["w"]), 200, 4000), clampi(int(cmd["h"]), 200, 4000))
	await _frames(4)
	return _ok({"window": [get_window().size.x, get_window().size.y]})


func _under(cmd: Dictionary) -> Dictionary:
	var at: Variant = _at_of(cmd)
	if at == null:
		return _fail("at needs x and y")
	var drawn := _drawn().filter(func(d: Dictionary) -> bool: return _rect(d).has_point(at))
	return _ok(
		{
			"topmost": _home._topmost(at - _main._room.global_position),
			"control": _describe(_control_at(_main, at)),
			"drawn": drawn.back() if not drawn.is_empty() else null,
		}
	)


func _at_of(cmd: Dictionary) -> Variant:
	if cmd.get("x") is float and cmd.get("y") is float:
		return Vector2(float(cmd["x"]), float(cmd["y"]))
	return null


func _point(value: Variant) -> Variant:
	if value is Array and value.size() == 2 and value[0] is float and value[1] is float:
		return Vector2(float(value[0]), float(value[1]))
	return null


func _motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - _mouse
	e.button_mask = _mask
	_mouse = at
	Input.parse_input_event(e)


func _press(at: Vector2, button: int, pressed: bool, double: bool = false) -> void:
	var bit := 1 << (button - 1)
	_mask = (_mask | bit) if pressed else (_mask & ~bit)
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = pressed
	e.double_click = double and pressed
	e.button_mask = _mask
	e.factor = 1.0
	Input.parse_input_event(e)


func _click(cmd: Dictionary) -> Dictionary:
	var at: Variant = _at_of(cmd)
	var button: Variant = BUTTONS.get(str(cmd.get("button", "left")))
	if at == null or button == null:
		return _fail("click needs x, y and a button of left, right or middle")
	_motion(at)
	await _frames(1)
	for round in 2 if cmd.get("double") == true else 1:
		_press(at, button, true, round == 1)
		await _frames(2)
		_press(at, button, false)
		await _frames(2)
	return _ok()


func _drag(cmd: Dictionary) -> Dictionary:
	var from: Variant = _point(cmd.get("from"))
	var to: Variant = _point(cmd.get("to"))
	if from == null or to == null:
		return _fail("drag needs from and to as [x, y]")
	var seconds := clampf(float(cmd.get("seconds", 0.4)), 0.0, 30.0)
	_motion(from)
	await _frames(1)
	_press(from, MOUSE_BUTTON_LEFT, true)
	var began := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var u := 1.0 if seconds == 0.0 else (Time.get_ticks_msec() - began) / 1000.0 / seconds
		if u >= 1.0:
			break
		_motion(from.lerp(to, u))
	_motion(to)
	await _frames(1)
	_press(to, MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	return _ok()


func _key_event(
	code: int, pressed: bool, text: String, shift: bool, ctrl: bool = false
) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.unicode = text.unicode_at(0) if text != "" else 0
	e.pressed = pressed
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	return e


# a named key, an F-key or one character; -1 when it is none of them
func _keycode(name: String) -> int:
	if NAMED.has(name.to_lower()):
		return NAMED[name.to_lower()]
	if name.length() == 1:
		return name.to_upper().unicode_at(0)
	if name.to_lower().begins_with("f") and name.substr(1).is_valid_int():
		return KEY_F1 + clampi(int(name.substr(1)), 1, 12) - 1
	return -1


func _key(cmd: Dictionary) -> Dictionary:
	var name := str(cmd.get("key", ""))
	var shift: bool = cmd.get("shift") == true
	var ctrl: bool = cmd.get("ctrl") == true
	var code := _keycode(name)
	if code < 0:
		return _fail("unknown key: %s" % name)
	var text := ""
	if name.length() == 1 and not ctrl:
		text = name.to_upper() if shift else name.to_lower()
	Input.parse_input_event(_key_event(code, true, text, shift, ctrl))
	await _frames(2)
	Input.parse_input_event(_key_event(code, false, "", shift, ctrl))
	await _frames(2)
	return _ok()


func _shot(cmd: Dictionary) -> Dictionary:
	var path := str(cmd.get("path", ""))
	if not path.is_absolute_path():
		return _fail("shot needs an absolute path")
	if DisplayServer.get_name() == "headless":
		return _fail("nothing is drawn: a headless run has no picture")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		return _fail("could not write %s: %s" % [path, error_string(err)])
	return _ok({"path": path, "size": [image.get_width(), image.get_height()]})


func _levers(cmd: Dictionary) -> Dictionary:
	var why := _lever(str(cmd.get("what")), cmd.get("value"))
	return _ok() if why == "" else _fail(why)


# the staging args' own code, live; "" when applied, else why not
func _lever(what: String, value: Variant) -> String:
	if what == "time" and value is String:
		if value == "":
			_home.fake_hour = -1.0
		else:
			_home.set_at(value)
	elif what == "date" and value is String:
		_home.fake_day = value
	elif what == "weather" and value is String:
		_home.forced_weather = value
	elif what == "pet" and value is String and "=" in value:
		var spec: Dictionary = _home.pets_spec(value)
		for key: String in spec:
			_home.settings.put(key, spec[key])
	elif what == "setting" and value is String:
		_main._put_staged(value)
	elif what == "setting" and value is Dictionary and _known(value):
		for key: String in value:
			_home.settings.put(key, value[key])
	else:
		return (
			'set what/value: time "HH:MM" ("" follows the clock), date "MM-DD" ("" is today), '
			+ 'weather KIND ("" is the real one), pet "cat=KIND,dog=KIND", '
			+ 'setting "key=value;..." or an object of settings keys'
		)
	return ""


func _known(value: Dictionary) -> bool:
	return value.keys().all(func(k: Variant) -> bool: return k in _home.settings.DEFAULTS)


func _rect(d: Dictionary) -> Rect2:
	var r: Array = d["rect"]
	return Rect2(r[0], r[1], r[2], r[3])


func _rect_of(r: Rect2) -> Array:
	return [
		snappedf(r.position.x, 0.1),
		snappedf(r.position.y, 0.1),
		snappedf(r.size.x, 0.1),
		snappedf(r.size.y, 0.1),
	]


func _centre(r: Rect2) -> Array:
	var c := r.get_center()
	return [roundi(c.x), roundi(c.y)]


func _label_of(c: Control) -> String:
	if c is Button or c is Label or c is LineEdit or c is TextEdit:
		return c.text
	var out: Array = []
	for l in c.find_children("*", "Label", true, false):
		if l.is_visible_in_tree():
			out.append(l.text)
	return " | ".join(out)


func _takes_input(c: Control) -> bool:
	if c is BaseButton or c is LineEdit or c is TextEdit or c is Range or c is TabBar:
		return true
	if c.mouse_filter != Control.MOUSE_FILTER_STOP:
		return false
	return not c.gui_input.get_connections().is_empty() or c.has_method("_gui_input")


func _visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null and r.size.x > 0.0 and r.size.y > 0.0:
		if p is Control and (p is ScrollContainer or p.clip_contents):
			r = r.intersection(p.get_global_rect())
		p = p.get_parent()
	return r


func _describe(c: Control) -> Variant:
	if c == null:
		return null
	var d := {
		"class": c.get_class(),
		"name": str(c.name),
		"text": _label_of(c),
		"rect": _rect_of(c.get_global_rect()),
	}
	if c is LineEdit:
		d["placeholder"] = c.placeholder_text
	if c is BaseButton:
		d["disabled"] = c.disabled
		if c.toggle_mode:
			d["pressed"] = c.button_pressed
	if c.tooltip_text != "":
		d["tooltip"] = c.tooltip_text
	return d


func _control_at(node: Node, at: Vector2) -> Control:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child := node.get_child(i)
		if not child is Control or not child.is_visible_in_tree():
			continue
		var inner := _control_at(child, at)
		if inner != null:
			return inner
		if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and _visible_rect(child).has_point(at):
			return child
	return null


func _controls() -> Array:
	var out: Array = []
	var window := Rect2(Vector2.ZERO, Vector2(get_window().size))
	for c in _main.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or not _takes_input(c):
			continue
		var r := _visible_rect(c)
		if r.size.x <= 0.0 or r.size.y <= 0.0 or r.get_area() > window.get_area() / 2.0:
			continue
		var d: Dictionary = _describe(c)
		d["center"] = _centre(r)
		out.append(d)
	return out


func _moved(r: Rect2, by: Vector2) -> Array:
	return _rect_of(Rect2(r.position + by, r.size))


func _drawn() -> Array:
	var out: Array = []
	var room: Vector2 = _main._room.global_position
	for b in _home.card._buttons:
		out.append({"src": "card", "act": b["act"], "rect": _moved(b["rect"], room)})
	if _home.menu.is_open:
		for i in _home.menu.rows.size():
			var label := str(_home.menu.rows[i].get("label", ""))
			out.append({"src": "menu", "label": label, "rect": _moved(_home.menu._rects[i], room)})
	if _home.rhythm.kind != "":
		for r: Rect2 in _home.rhythm._rects:
			out.append({"src": "slip", "rect": _moved(r, room)})
	if _main._decorate.active:
		var at: Vector2 = _main._decorate.global_position
		for h in _main._decorate._hits:
			out.append({"src": "decorate", "act": h["act"], "rect": _moved(h["rect"], at)})
	for d in out:
		d["center"] = _centre(_rect(d))
	return out


func _registered() -> Array:
	var out: Array = []
	var room: Vector2 = _main._room.global_position
	for c in _home.pets.critters:
		if not c.away:
			var r: Rect2 = _home.pets.hit_rect(c, _home._o, _home._k)
			var key: String = c.id if c.id == "person" else "pet:" + c.id
			var at := _centre(Rect2(r.position + room, r.size))
			var reach: bool = _home._topmost(Vector2(at[0], at[1]) - room) == key
			out.append({"key": key, "center": at, "reachable": reach})
	for h in _home._hits:
		var sum := Vector2.ZERO
		for p: Vector2 in h["poly"]:
			sum += p
		var c: Vector2 = sum / maxf(1.0, h["poly"].size())
		var row := {
			"key": h["key"],
			"center": [roundi(c.x + room.x), roundi(c.y + room.y)],
			"reachable": _home._topmost(c) == h["key"],
		}
		out.append(row)
	return out


func _mode() -> Dictionary:
	var m := _main
	return {
		"room": m._at,
		"decorate": m._decorate.active,
		"closet": m._closet.visible,
		"settings": m._settings_view.visible,
		"chat": m._chat_view.visible,
		"pet_card": m._pet_view.role if m._pet_view.visible else "",
		"form": m._form.kind if m._form.visible else "",
		"card": _home.card.kind,
		"menu": _home.menu.is_open,
		"jot": m._jot.visible,
		"slip": _home.rhythm.kind,
		"widget": m._widget,
	}


func _things(_cmd: Dictionary = {}) -> Dictionary:
	return _ok(
		{
			"window": [get_window().size.x, get_window().size.y],
			"mode": _mode(),
			"registered": _registered(),
			"controls": _controls(),
			"drawn": _drawn(),
		}
	)


func _pets() -> Array:
	var out: Array = []
	for c in _home.pets.critters:
		if c.id == "person":
			continue
		var cell: Vector2i = _home.pets._cell_of(c.pos)
		var row := {
			"id": c.id,
			"kind": _home.pets.kinds[c.id],
			"name": _home.settings.cat if c.id == "nina" else _home.settings.dog,
			"personality": _home.pets.personalities[c.id],
			"cell": [cell.x, cell.y],
			"anim": c.anim,
			"mode": c.mode,
			"spot": c.spot,
			"antic": str(c.plan.get("mode", "")),
			"says": c.say_text if c.say_left > 0.0 else "",
			"away": c.away,
		}
		out.append(row)
	return out


func _state(_cmd: Dictionary = {}) -> Dictionary:
	var items: Array = []
	for t in _main._data["open"]:
		var row := {
			"id": int(t["id"]),
			"kind": t.get("kind"),
			"text": t.get("text"),
			"when": t.get("due_at"),
			"every": t.get("every"),
		}
		items.append(row)
	var settings := {}
	for key: String in _home.settings.DEFAULTS:
		settings[key] = _home.settings.value(key)
	var hour: float = _home._hour()
	return _ok(
		{
			"open": items,
			"coming": _main._data["coming"].size(),
			"pets": _pets(),
			"person": _home.person.act,
			"tv": _home.tv.on,
			"fire": _home.fire_on(),
			"weather": _home.weather if _home.forced_weather == "" else _home.forced_weather,
			"clock": "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)],
			"date": _home.today(),
			"night": _home.pets.is_night,
			"settings": settings,
			"pieces": _home.layout.pieces.size(),
			"layout": _home.layout.pieces,
			"said": _said,
			"mode": _mode(),
			"errors": null,
		}
	)
