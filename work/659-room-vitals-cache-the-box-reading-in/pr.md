Room.vitals/0 cached its box reading (tmux, disk, memory) in `:persistent_term`, replacing it every 60 s. Each `:persistent_term.put` that replaces a value triggers a global GC, so the cache itself was costing a GC a minute.

The reading now lives in a named public ETS table, `Server.Office.Room`, created by `Room.init_vitals/0` from `Application.start/2` next to `Server.MCP.Tool.init_fence/0`. `vitals/1` takes `now` (default: monotonic clock) and reads with `:ets.lookup`, refreshing when the reading is a minute old, as `cut_tools/3` does. Only vitals changes; the same TTL-on-persistent_term shape in held_windows, ollama_window, rollout, attention and needs is a separate follow-up.

Closes #659.

Checked: one new test in `room_test.exs` ("vitals: a reading serves the next minute from the table, a read past it refreshes"). It was red before the change (`ArgumentError`: no ETS table, `vitals/1` undefined) and green after; the whole `room_test.exs` file is 23 tests, 0 failures. The server gate (`menard run check --in server`) passed on the commit: 2535 tests, 0 failures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
