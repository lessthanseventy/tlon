APPROVE — right then. Read the diff (7bcd23e) by eye; I did not run the suite (builder reports 10 tests green via menard).

What it does: `Tools.run/4` takes `in:`; default is root if it has a mix.exs, else the single immediate subdir that does; zero/several are refused naming candidates; `format` stays root-relative. `run_verb` gains the `in` field; AGENTS.md updated in the same commit. Tests cover default, root-wins, explicit `in`, none/several, escape. Scope is surgical and matches the ask (#441).

Non-blocking:
- `in: "."` (or `""`) is refused as "outside the thread's worktree": `resolve_all` requires `abs` to start with `root <> "/"`, and `Path.expand(".", root) == root`. `.` is the natural way to say "the root" when a subdir also has a mix.exs. The default path never hits it.
- `in:` naming a nonexistent dir passes `resolve_all` and falls through to Menard's error rather than a clear refusal here.
- No bench row involved; no flake to judge.