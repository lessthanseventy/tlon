extends RefCounted

# One prompt asked of the `claude` command-line program, for the money chat: `<command> -p <prompt>
# --model haiku --output-format json --tools ""`, a process of its own with the prompt one argument,
# stdin closed and `limit` seconds. `ask(prompt, cb)` answers `cb(ok, text)` on a later frame: the
# model's text, or ok false and why it is not one (not found, timed out, exit N and its first line).
const ReaderClaude := preload("res://reader_claude.gd")

var command := "claude"
var limit := 60.0


func ask(prompt: String, cb: Callable) -> void:
	var path := ReaderClaude.which(command)
	if path == "":
		cb.call_deferred(false, "%s not found on PATH" % command)
		return
	var spawned := _spawn(path, prompt)
	if spawned.is_empty():
		cb.call_deferred(false, "%s could not start" % path)
		return
	var pid: int = spawned["pid"]
	# a bound Callable does not hold its object: the box does, until the run is over
	var box := {"timed_out": false, "over": false, "keep": self}
	Engine.get_main_loop().create_timer(limit).timeout.connect(
		func() -> void:
			if not box["over"] and OS.is_process_running(pid):
				box["timed_out"] = true
				OS.kill(pid)
	)
	var thread := Thread.new()
	thread.start(_collect.bind(spawned, thread, box, cb))


static func _spawn(path: String, prompt: String) -> Dictionary:
	var args := ["-p", prompt, "--model", "haiku", "--output-format", "json", "--tools", ""]
	if OS.get_name() == "Windows":
		if path.get_extension().to_lower() in ["cmd", "bat"]:
			args = [
				"-p",
				ReaderClaude._batch_safe(prompt),
				"--model",
				"haiku",
				"--output-format",
				"json"
			]
		return OS.execute_with_pipe(path, args)
	return OS.execute_with_pipe("/bin/sh", ["-c", 'exec "$0" "$@" </dev/null', path] + args)


static func _drain(io: Variant) -> String:
	var out := PackedByteArray()
	if not io is FileAccess:
		return ""
	while true:
		var part: PackedByteArray = io.get_buffer(4096)
		out.append_array(part)
		if part.size() < 4096:
			break
	return out.get_string_from_utf8()


func _collect(spawned: Dictionary, thread: Thread, box: Dictionary, cb: Callable) -> void:
	var out := _drain(spawned["stdio"])
	var err := _drain(spawned.get("stderr"))
	var pid: int = spawned["pid"]
	var code := -1
	if not box["timed_out"]:
		for _i in 200:
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(10)
		code = OS.get_process_exit_code(pid)
	_finish.call_deferred(thread, box, code, out, err, cb)


func _finish(
	thread: Thread, box: Dictionary, code: int, out: String, err: String, cb: Callable
) -> void:
	thread.wait_to_finish()
	box["over"] = true
	var json := JSON.new()
	var envelope: Variant = json.data if json.parse(out) == OK else null
	var said: String = (
		envelope["result"] if envelope is Dictionary and envelope.get("result") is String else ""
	)
	if box["timed_out"]:
		cb.call(false, "timed out after %ds" % int(limit))
	elif code != 0 or (envelope is Dictionary and envelope.get("is_error") == true):
		cb.call(false, "exit %d: %s" % [code, first_line([said, err, out])])
	elif said == "":
		cb.call(false, "no reply")
	else:
		cb.call(true, said)


# the first non-blank line of the first text that has one, at most 160 characters
static func first_line(texts: Array) -> String:
	for t in texts:
		for line in str(t).split("\n"):
			if line.strip_edges() != "":
				return line.strip_edges().left(160)
	return "no output"
