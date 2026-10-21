# #494 — fixture door for `start_smoke`: plan

Spec: `spec.md` beside this file (decided: A, named seed sets). Four tasks, each one commit, in order.
Run Elixir tests with `~/projects/menard/bin/menard run test --in server <file>`; edit Elixir with
menard. Gate before advancing: `menard run check --in server` (a seat never runs `mise run check`).

Facts the tasks rest on (read from the code):
- `Server.Smoke.start(thread, ref, by \\ nil, flags \\ [])` — `server/lib/server/smoke.ex`; flags are
  checked with `~r/\A[a-z][a-z0-9_]*\z/` and dropped from job args when `[]` (`Map.reject`).
- `Server.Jobs.Smoke.perform/1` — `server/lib/server/jobs/smoke.ex` — env `TLON_SMOKE_FLAGS`.
- `StartSmoke` — `server/lib/server/mcp/tools/smoke.ex`.
- `scripts/release-smoke.sh` — flag loop at "TLON_SMOKE_FLAGS"; node started with
  `TLON_NODE=tlon-smoke-$port@127.0.0.1 TLON_DATABASE=$db`; db is `tlon_smoke_<port>`.
- A `tool_denied` Need (`Server.Office.Needs.tool_denied/2`) is an open thread with ≥2 `tool_denied`
  events since it last moved and nobody on duty. Event shape: see `deny/2` in
  `server/test/server/office/needs_test.exs`.

## Task 1 — `Server.Smoke.Fixtures` (catalog + db guard)

Files: new `server/lib/server/smoke/fixtures.ex`, new `server/test/server/smoke/fixtures_test.exs`.

Test first (red: module missing):
```elixir
defmodule Server.Smoke.FixturesTest do
  use ExUnit.Case, async: false
  alias Server.Smoke.Fixtures

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "names/0 lists the catalog" do
    assert "tool_denied_need" in Fixtures.names()
  end

  test "tool_denied_need seeds an open thread the Needs list reports as tool_denied" do
    assert :ok = Fixtures.apply("tool_denied_need", "tlon_smoke_4100")
    assert [%{kind: "tool_denied", level: "blocking"}] = Server.Office.Needs.list()
  end

  test "an unknown name raises" do
    assert_raise ArgumentError, ~r/unknown fixture "nope"/, fn -> Fixtures.apply("nope", "tlon_smoke_4100") end
  end

  test "any db that is not tlon_smoke_* is refused, seeding nothing" do
    assert_raise ArgumentError, ~r/tlon_smoke_/, fn -> Fixtures.apply("tool_denied_need", "tlon") end
    assert [] = Server.Office.Needs.list()
  end
end
```
Code (`apply/1` reads the repo's db name; `apply/2` takes it, for the test — the suite's own db is
not `tlon_smoke_*`):
```elixir
defmodule Server.Smoke.Fixtures do
  @moduledoc """
  The closed catalog of seed sets a smoke can be started with (`start_smoke`'s `fixtures`). Each runs
  inside the smoke node, through the server's own contexts, so seeded rows pass the live
  validations. It ships with the candidate build: the catalog is the review surface for what a smoke
  can be made to believe. Refuses any database that is not a scratch `tlon_smoke_*` one.
  """

  @doc "Run the fixture `name` on this node's database (`rpc`'d by `scripts/release-smoke.sh`)."
  def apply(name), do: apply(name, Server.Repo.config()[:database])

  @doc false
  def apply(name, database) do
    unless is_binary(database) and String.starts_with?(database, "tlon_smoke_"),
      do: raise(ArgumentError, "fixtures run only on a tlon_smoke_* database, not #{inspect(database)}")

    case Map.fetch(catalog(), name) do
      {:ok, seed} -> seed.()
      :error -> raise ArgumentError, "unknown fixture #{inspect(name)}: #{Enum.join(names(), ", ")}"
    end
  end

  def names, do: catalog() |> Map.keys() |> Enum.sort()

  defp catalog, do: %{"tool_denied_need" => &tool_denied_need/0}

  defp tool_denied_need do
    {:ok, t} = Server.Channel.open_thread(%{title: "fixture: a refused tool"})

    for _ <- 1..2 do
      {:ok, _} =
        Server.Dossier.record_event(%{
          thread_id: t.id,
          kind: "tool_denied",
          correlation: "tool_denied:#{t.id}",
          detail: %{"agent" => "fixture", "tool" => "Bash", "summary" => "Bash · echo hi", "reason" => "fixture"}
        })
    end

    :ok
  end
end
```
Adjust `open_thread` attrs to what `Thread.open_changeset` requires (the test will say). Beware
`Kernel.apply/2` clashes with a local `apply/2`: if the compiler complains, rename to `seed/1,2` and
use that name in Tasks 3–4 (spec says `apply`; keep `apply` if it compiles).

Done: the four tests green — `menard run test --in server server/test/server/smoke/fixtures_test.exs`.
Commit: `smoke: a closed catalog of fixtures, guarded to tlon_smoke_* dbs`.

## Task 2 — `Smoke.start/5` carries `fixtures`; `StartSmoke` accepts them

Files: `server/lib/server/smoke.ex`, `server/lib/server/mcp/tools/smoke.ex`,
`server/test/server/jobs/smoke_test.exs` (where `Smoke.start` is already tested; follow its `setup`).

Tests first (red):
```elixir
test "start/5 carries fixtures into the job args, and omits them when empty", %{thread: t} do
  {:ok, job} = Smoke.start(t, nil, "qa1", [], ["tool_denied_need"])
  assert job.args["fixtures"] == ["tool_denied_need"]
  Smoke.stop(t.id)  # or cancel the job as the neighbouring tests do
  {:ok, job2} = Smoke.start(t, nil, "qa1", [], [])
  refute Map.has_key?(job2.args, "fixtures")
end

test "start/5 rejects a malformed fixture name", %{thread: t} do
  assert {:error, "not a fixture name: " <> _} = Smoke.start(t, nil, "qa1", [], ["Bad Name; rm"])
end
```
(Two starts on one thread hit `held/1` only once a job is executing and up; use two threads or
cancel if the neighbours do — copy their pattern.)

Code: add `fixtures \\ []` after `flags`; one shared name regex (`@name ~r/\A[a-z][a-z0-9_]*\z/`) used
by flags and fixtures, a `cond` clause
`Enum.any?(fixtures, &(!Regex.match?(@name, &1))) -> {:error, "not a fixture name: #{inspect(fixtures)}"}`,
and `fixtures: fixtures` in the `Map.reject` map. In `StartSmoke`:
`field :fixtures, {:list, :string}, description: "Named seed sets to load into the smoke's own database before you drive it (e.g. [\"tool_denied_need\"]); the build's catalog, an unknown name fails the smoke"`
and pass `params[:fixtures] || []` as the last arg. Not-QA stays refused by `QASmoke.thread/2` (unchanged).

Done: new tests + neighbours in that file green; `menard run test --in server server/test/server/jobs/smoke_test.exs`.
Commit: `start_smoke: a fixtures argument, validated by name`.

## Task 3 — `Jobs.Smoke` exports `TLON_SMOKE_FIXTURES`

Files: `server/lib/server/jobs/smoke.ex`, `server/test/server/jobs/smoke_test.exs`.

Test first (red): extend the stub script in that file's pattern with a variant that echoes the env
(`echo "fixtures=$TLON_SMOKE_FIXTURES"` before the hold line; the job's log file is
`tlon-smoke-job-<id>.log`), start with `fixtures: ["a_set", "b_set"]`, assert the log contains
`fixtures=a_set b_set`. Without fixtures it contains `fixtures=`.

Code: one more env tuple beside `TLON_SMOKE_FLAGS`:
`{~c"TLON_SMOKE_FIXTURES", String.to_charlist(Enum.join(job.args["fixtures"] || [], " "))}`.

Done: green; commit `smoke job: pass the fixtures to the script`.

## Task 4 — `release-smoke.sh` applies them on the smoke node

Files: `scripts/release-smoke.sh`, `server/test/server/release_smoke_script_test.exs`.

Test first (red), beside the flag test (same `FlagStub`, `TLON_SMOKE_URL` mode): a stub rpc binary in
a tmp dir —
`#!/usr/bin/env bash` / `[[ "$*" == *'Fixtures.apply("ok_set")'* ]]` — exits 0 for `ok_set`, 1 for
anything else; env `TLON_SMOKE_SERVER_BIN=<stub>` and `TLON_SMOKE_FIXTURES`:
- `"ok_set"` → exit 0, output has `smoke: fixture ok_set seeded`.
- `"nope"` → exit 1, output has `fixture nope:`.
- fixtures with no scratch node and no `TLON_SMOKE_SERVER_BIN` (URL mode) → exit 1,
  `fixtures need a scratch node`.

Code, right after the flag loop and before `[ -n "$home" ]`:
```bash
# TLON_SMOKE_FIXTURES: named seed sets (`start_smoke`'s fixtures) run INSIDE this node: only the
# candidate build knows its own catalog, and Fixtures.apply refuses any db but tlon_smoke_*
fixtures="${TLON_SMOKE_FIXTURES:-}"
server_bin="${TLON_SMOKE_SERVER_BIN:-${dir:+$dir/server/_build/prod/rel/server/bin/server}}"
for fx in $fixtures; do
  [ -n "$server_bin" ] || fail "fixtures need a scratch node (not TLON_SMOKE_URL)"
  TLON_NODE="tlon-smoke-$port@127.0.0.1" TLON_DATABASE="$db" \
    "$server_bin" rpc "Server.Smoke.Fixtures.apply(\"$fx\")" >>"$log" 2>&1 ||
    fail "fixture $fx: not seeded (an unknown name in this build? see $log)"
  echo "smoke: fixture $fx seeded"
done
```
Check `$log` is defined in URL mode (`grep -n 'log=' scripts/release-smoke.sh`); if not, send to
`/dev/null` there. Names are grammar-checked in Task 2, so `$fx` cannot break the quoting.
Verify the real wiring once by hand: `mise run release:smoke` with
`TLON_SMOKE_FIXTURES=tool_denied_need` (unsandboxed, one smoke at a time) — expect
`smoke: fixture tool_denied_need seeded`; then `curl $url/api/office` shows the Need. If the rpc
cannot find the node, the release's `RELEASE_NODE`/cookie env is the first suspect.

Docs, same commit: one line each in `scripts/release-smoke.sh`'s header (next to TLON_SMOKE_FLAGS) and
wherever `start_smoke`'s `flags` is described to QA (`grep -rn "start_smoke" docs server/AGENTS.md`).

Done: `menard run test --in server server/test/server/release_smoke_script_test.exs` green;
`menard run check --in server` green. Commit: `release-smoke: seed fixtures on the smoke node`.

## Hand-off
Advance to build after the plan is approved. Live proof (QA, after release): `start_smoke` with
`fixtures: ["tool_denied_need"]`, then drive the Need's verb in the TUI.
