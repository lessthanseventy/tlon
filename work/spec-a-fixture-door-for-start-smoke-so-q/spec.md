# #494 — a fixture door for `start_smoke`: spec

QA can't drive verbs that act on state a fresh smoke db lacks (a Need, a denied tool, a held gate).
`start_smoke` has `flags` today; it has no way to seed rows. This adds one.

**Decided (operator, #10626): A, named seed sets only.** The `tlon_smoke_*` db guard stays a must.

## 1 · What exists, reused

- `Server.MCP.Tool.StartSmoke` → `Server.Smoke.start/4` → `Server.Jobs.Smoke` (env `TLON_SMOKE_FLAGS`)
  → `scripts/release-smoke.sh`, which applies each flag on the smoke node through its own API and
  fails the smoke on a name the build lacks.
- The smoke runs on its own db `tlon_smoke_<port>` (`TLON_SMOKE_DATABASE`), created and dropped by
  the script; one smoke per commit (flock); one held smoke per thread (`Smoke.held/1`).
- Authority: `start_smoke` already refuses all but a `qa` seat on that workline's bench
  (`Tool.QASmoke.thread/2`).

## 2 · What a fixture is

A **named seed set**: an Elixir function in a closed catalog, `Server.Smoke.Fixtures`
(`server/lib/server/smoke/fixtures.ex`), `name :: String.t() => (-> :ok)`. It inserts rows through the
server's own contexts (not raw SQL), so every seeded row passes the same validations as a live one.
It lives in the candidate build, so a fixture always matches the schema of the code under test.

First catalog entry: `tool_denied_need` — a thread with one open `tool_denied` Need (the case #494
was filed for). Further sets are added by the change that needs them, with a test.

Names use the flag-name grammar (`\A[a-z][a-z0-9_]*\z`). `Fixtures.names/0` lists them.

## 3 · Who may seed, from which seat

Only a `qa` seat on that workline's bench, through `start_smoke`'s new `fixtures: [name]` argument
(`{:list, :string}`, like `flags`). Same gate as `start_smoke` itself; no new permission, no other
tool, no HTTP route on the live server. Seeding happens **once, at start**. A different set means
`stop_smoke` and a new start.

Why not inline data (B): a seat would then write arbitrary rows, and the catalog is the review
surface for what a smoke can be made to believe. Not "C": the escape hatch is B's problem too.

## 4 · How it runs and stays apart

1. `Smoke.start/4` validates names against the grammar only (the live server's catalog is the live
   build's, not the candidate's). It passes `fixtures` in the job args; `Jobs.Smoke` exports `TLON_SMOKE_FIXTURES` (space-joined, as flags).
2. `release-smoke.sh`, after the flags loop and before the drive, runs for each name
   `"$node/bin/server" rpc 'Server.Smoke.Fixtures.apply("NAME")'` against the **smoke node**.
   Unknown name or any error raises → the smoke fails (`fail "fixture NAME: …"`), as a bad flag does.
3. `Fixtures.apply/1` **refuses unless the node's repo database name matches `tlon_smoke_*`**, so it
   cannot run on the live db even if called by mistake.
4. Isolation is the smoke's own db, one per port, dropped with the smoke; concurrent smokes have
   different ports/dbs, so a seed in one is invisible to another. No change to the lock.

Step 2 owns unknown-name, because only the candidate build knows its own catalog.

## 5 · Out of scope

Inline/JSON seeds; seeding a running smoke; fixtures for `mise run release:smoke`'s default run;
mutating or reading the live db.

## 6 · Verify

- `Server.Smoke.start/4`: rejects a malformed fixture name; carries `fixtures` into job args; omits
  it when empty (existing `Map.reject`).
- `Fixtures.apply/1`: `tool_denied_need` creates the Need on a `tlon_smoke_*` db; raises on an
  unknown name; raises on any other db name.
- `Jobs.Smoke`: sets `TLON_SMOKE_FIXTURES` from args.
- `StartSmoke` tool: accepts `fixtures`; non-QA still refused.
- Script: `release-smoke.sh` fails the smoke on an unknown fixture (shell test beside the flag one);
  `mise run check` green. Live: QA starts a smoke with `fixtures: ["tool_denied_need"]` and drives
  the Need's verb.
