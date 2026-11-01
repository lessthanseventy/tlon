# Plan — #664 persist Needs health first-seen

Scope: `Server.Office.Needs.health_since/1` only. `Attention.tmux_down/2` is OUT (own ticket).
Storage: schemaless table `health_since` (`what` text PK, `since` utc_datetime), same shape as
`need_heard` (migration `20261022010000_need_heard.exs`, queried schemaless in needs.ex). No schema module.
Semantics: a row exists exactly while its problem holds. Each read: insert rows for new problems
(`on_conflict: :nothing`), delete rows for problems no longer holding, return `%{what => since}`.
`what` is an atom in problems (`:tmux`, `:disk`, `:mem`); store `Atom.to_string`, return atom keys
(`since[what]` in `health/0` is atom-keyed).

## Task 1 — migration + doctor table list (commit 1)
Test first: add `"health_since"` (alphabetical, after `"habit"`) to the table list in
`server/test/server/doctor_test.exs` (~line 18). Run `menard run test --in server test/server/doctor_test.exs` → red.
Create `server/priv/repo/migrations/20261031120000_health_since.exs`:
```elixir
defmodule Server.Repo.Migrations.HealthSince do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:health_since, primary_key: false) do
      add :what, :string, primary_key: true
      add :since, :utc_datetime, null: false
    end
  end
end
```
Done: doctor_test green (`menard run test --in server test/server/doctor_test.exs`). If doctor.ex hardcodes tables, add there too (grep showed no `need_heard` in doctor.ex, so likely not).

## Task 2 — persist in Needs (commit 2)
Tests first, in `server/test/server/office/needs_test.exs` (health describe, ~1410–1480):
- `on_exit` (line ~1420): replace `:persistent_term.erase({Needs, :health_since})` with `Server.Repo.delete_all("health_since")`.
- line ~1463: replace `:persistent_term.put({Needs, :health_since}, %{tmux: since})` with
  `Server.Repo.insert_all("health_since", [%{what: "tmux", since: DateTime.truncate(since, :second)}])`
  (clear first with `Repo.delete_all("health_since")` if a prior read already stamped it).
- Replace test at ~1469 ("a restart starts … (open: not persisted)") with:
  "a held health item keeps its first-seen across a restart": seed row `tmux` at -3600s via insert_all; `assert [%{key: "health:tmux", at: ^since}] = Needs.list()` (since truncated to seconds). No erase step — the db row *is* the restart-surviving state.
- New test "a resolved problem's row is cleared": hold tmux, `Needs.list()`, assert row exists; flip reading to healthy (`health_reading(%{tmux: true, disk_pct: 10, mem_pct: 10})`), `Needs.list()`, assert `Repo.all(from h in "health_since", select: h.what) == []`; flip back to down → `at` is new (> old since).
Run → red (`menard run test --in server test/server/office/needs_test.exs`).

Impl in `server/lib/server/office/needs.ex`, replace `health_since/1` (~1162) and its comment:
```elixir
  # When each problem was first seen, so its `at` is stable across reads and restarts: a verdict or a
  # put-away is only ever newer than it. A row lives exactly while its problem holds.
  defp health_since(problems) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    whats = Enum.map(problems, fn {what, _} -> to_string(what) end)

    Repo.delete_all(from h in "health_since", where: h.what not in ^whats)

    if whats != [] do
      Repo.insert_all("health_since", Enum.map(whats, &%{what: &1, since: now}), on_conflict: :nothing, conflict_target: :what)
    end

    stored = Map.new(Repo.all(from h in "health_since", select: {h.what, type(h.since, :utc_datetime)}))
    Map.new(problems, fn {what, _} -> {what, stored[to_string(what)]} end)
  end
```
(Reads now hit the db; `health/0` already `rescue`s, so a db failure leaves health items out, as before. If perf matters, YAGNI: the inbox read already does several Repo queries.)
Also grep `server/AGENTS.md`/`server/docs/spec.md` for `health_since`/persistent_term mention of Needs and update in the same commit.
Done: `menard run test --in server test/server/office/needs_test.exs` green; then `menard run check --in server` green.

## Out of scope
`Attention.tmux_down/2` (persistent_term key `{Attention, :down, ws}`): separate ticket — suggest/file it, don't touch.
