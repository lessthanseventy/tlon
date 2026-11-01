## run_verb refuses `check` and points at `run_task`

Closes #709.

**What was wrong.** A gate runs for minutes (the server suite alone reads 190 to 440 s in the verify
logs), longer than one MCP tool call lives. Past the transport's request timeout the handler's call into
the anubis session dies, the response stream turns the exit into a protocol error, and anubis renders
every protocol error to the client as the bare "Internal error" (detail only in `data`, which Claude Code
hides). Mix kept running in the session's one in-flight task meanwhile, queueing the seat's next calls.
#703 raises the transport's bound to 200 s for the office drive; `check` outruns that too, so the fix for
`check` is in `run_verb`, not the gateway. Not #700's family (a raise in a clause verb) and not #571.

**What changed.** The async door already exists: `run_task` runs a mise task on the committed head off
the seat and posts the result to the caller. So `Server.Source.Tools.run/4` refuses `:check` with that
pointer ("commit, then `run_task("server:check")`; its result is posted to you"), and `test`, `format`
and `compile` are unchanged. Not an enqueue from inside `run_verb`: `run_task` runs the committed head
and `run_verb` the working tree, and swapping one for the other silently would lie about what was
checked. The RunVerb moduledoc and the root `AGENTS.md` sentence on `run_verb` say the same; that
sentence is a limit, so this gate is the operator's.

**How it was checked.** Test-first: the new test in `test/server/source/tools_test.exs` was red for the
stated cause (`Tools.run(t, :check, [])` ran mix and answered a result), then green:

```
menard run test --in server test/server/source/tools_test.exs
{"ok":true,"tests":16,"failed":0,"failures":[]}
```

`server:check` on the head is run through `run_task`; its result is on thread #517.

**Left open, on purpose.** A `run_verb test` that compiles cold can still outrun #703's 200 s and read
"Internal error". Ticket #797 holds the follow-up: forward a deadline under the gateway's bound once
#703's constant is on main. Not done here because it would edit `gateway.ex`, #703's file.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
