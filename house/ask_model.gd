extends RefCounted

# One prompt asked of the `claude` command-line program, for the money chat: `<command> -p <prompt>
# --model haiku --output-format json --tools ""`, a process of its own with the prompt one argument,
# stdin closed and `limit` seconds. `ask(prompt, cb)` answers `cb(ok, text)` on a later frame: the
# model's text, or ok false for anything that is not one (not found, timed out, an error).
const ReaderClaude := preload("res://reader_claude.gd")

var command := "claude"
var limit := 60.0


func ask(prompt: String, cb: Callable) -> void:
	var path := ReaderClaude.which(command)
	if path == "":
		cb.call_deferred(false, "")
		return
	var spawned := _spawn(path, prompt)
	if spawned.is_empty():
		cb.call_deferred(false, "")
		return
	var pid: int = spawned["pid"]
	var box := {"timed_out": false, "over": false}
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


func _collect(spawned: Dictionary, thread: Thread, box: Dictionary, cb: Callable) -> void:
	var out := PackedByteArray()
	var io: FileAccess = spawned["stdio"]
	while true:
		var part := io.get_buffer(4096)
		out.append_array(part)
		if part.size() < 4096:
			break
	var pid: int = spawned["pid"]
	var code := -1
	if not box["timed_out"]:
		for _i in 200:
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(10)
		code = OS.get_process_exit_code(pid)
	_finish.call_deferred(thread, box, code, out.get_string_from_utf8(), cb)


func _finish(thread: Thread, box: Dictionary, code: int, out: String, cb: Callable) -> void:
	thread.wait_to_finish()
	box["over"] = true
	var json := JSON.new()
	var envelope: Variant = json.data if code == 0 and json.parse(out) == OK else null
	if (
		box["timed_out"]
		or not envelope is Dictionary
		or envelope.get("is_error") == true
		or not envelope.get("result") is String
	):
		cb.call(false, "")
	else:
		cb.call(true, envelope["result"])
