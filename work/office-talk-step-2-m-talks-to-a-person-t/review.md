APPROVE.

Read the diff (office/tui/talk.ts, main.ts, talk.test.ts, AGENTS.md). I did not re-run the tests; the thread's recorded `mise run check` was green (exit 0).

- `talk.ts` is small and does what the plan says: it finds the workspace's standing thread, prefixes `@name ` for a person, and posts via the existing `data.post`.
- Empty text and a missing lobby return a status string and post nothing.
- `main.ts`: `m` on the coworker card calls `talk(name)` and `'` calls `talk(null)`. The model picker moved to `M`. Nothing else in `main.ts` or `AGENTS.md` still uses `m` for the model picker. `did()` takes the promise `say` returns.
- The `'` hint is in GLOBALS and `AGENTS.md` names `talk.ts`, so the docs match the code.
- The test posts to a local `Bun.serve` through `TLON_URL`, which `data.ts` reads per call, so it never touches the live server.

Nits, not blocking:
- `talk()` guards on `ws === null`, so `lobbyOf`'s null-workspace parameter is dead weight. Harmless.
- A person who isn't on the lobby gets @-mentioned there, which is the intended design.