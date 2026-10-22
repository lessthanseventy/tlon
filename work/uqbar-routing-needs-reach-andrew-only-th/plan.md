# Plan: Uqbar routing (#578) — spec.md beside this file is the contract

Server tasks 1–5 first (each green alone, flag off == #326's behaviour), then the office tasks 6–8, then docs 9.
Run tests: `~/projects/menard/bin/menard run test --in server <file>`; edit Elixir with menard. One commit per task.
Verify per task = that task's test file green AND `menard run test --in server server/test/server/office/needs_test.exs` still green (the #326 tests are the flag-off proof).
Baseline facts (read before starting): `Needs.all/0` builds items; `annotate/1` adds `surface`; `list/0` filters `need_dismissal`; `grouped/1` filters `need_heard` and groups; `prune/3` (table, rows-by-key, items) drops rows whose key left the list.

## Decisions I made (shout if wrong)
1. **Caller arg.** `settle`/`pass_up` need to know who calls, and a context function has no frame. Signatures: `settle(key, why, by)`, `pass_up(key, why, recommendation, by)` where `by` is the MCP identity's handle (`Identity.from_frame(frame).agent`). Gate = `by == "uqbar"` else `{:error, :forbidden}`. This is the same `identity.agent` that `Tool.steers?/2` reads; there is no existing "seat-only by handle" helper to reuse, so this is the one place it is checked.
2. Internal route `"settled"` exists beside `uqbar|pass_up|info`; it never leaves `Needs` (those items go to the `settled` group).
3. Flag off ignores rows entirely (checked before the row), so stale rows cannot hide anything.
4. A row applies only if `row.at >= item.at` (newer item under the key = new item).

## T1 — flag + rule table  (`server/lib/server/flags.ex`, `needs.ex`, tests `flags_test`?, `needs_test.exs`)
Test first (needs_test.exs):
```elixir
test "every kind has a pass-up rule" do
  for k <- Needs.kinds(), do: assert(Needs.pass_up_rule(k) in [:always, :info] or match?({:when, [_ | _]}, Needs.pass_up_rule(k)))
  assert Needs.pass_up_rule("tool_denied") == :always
  assert Needs.pass_up_rule("mention") == :info
  assert {:when, r} = Needs.pass_up_rule("pr_blocked"); assert r == [:host_command]
  assert_raise FunctionClauseError, fn -> Needs.pass_up_rule("nope") end
end
```
Also (follow the existing flags test, `grep -rl Flags server/test`): `Server.Flags.enabled?(:uqbar_routing) == false` by default.
Code: in `flags.ex` `@known [:build_mode, :judged_supersede, :uqbar_routing]` + comment `# :uqbar_routing — conditional needs route through Uqbar (Server.Office.Needs); off routes them all as pass_up`.
In `needs.ex` (no catch-all, mirrors `surface/1`):
```elixir
@always ~w(seats quota tool_denied)
@broad [:irreversible, :outward, :costly, :host_command, :auto_land_risk]
@narrow [:irreversible, :host_command]
@host [:host_command]

@doc "When a kind reaches the operator: `:always`, `:info` (never routed) or `{:when, reasons}` — only if Uqbar finds one holds."
def pass_up_rule(k) when k in @always, do: :always
def pass_up_rule(k) when k in ~w(mention rollout), do: :info
def pass_up_rule(k) when k in ~w(gate question dialog ask no_seat), do: {:when, @broad}
def pass_up_rule(k) when k in ~w(issue stalled verify_failed job_failed stranded), do: {:when, @narrow}
def pass_up_rule(k) when k in ~w(pr_blocked publish_failed release_failed), do: {:when, @host}
```
Done: `menard run test --in server server/test/server/office/needs_test.exs` green.

## T2 — migration + routed grouped/1  (`server/priv/repo/migrations/20261022020000_need_routing.exs`, `needs.ex`)
Migration (copy `need_heard`'s shape):
```elixir
defmodule Server.Repo.Migrations.NeedRouting do
  @moduledoc false
  use Ecto.Migration
  def change do
    create table(:need_routing, primary_key: false) do
      add :key, :string, primary_key: true
      add :state, :string, null: false
      add :why, :text
      add :recommendation, :text
      add :at, :utc_datetime, null: false
    end
  end
end
```
Tests first (new `describe "routing"`; setup: `FunWithFlags.enable(:uqbar_routing)`, `on_exit(fn -> FunWithFlags.disable(:uqbar_routing) end)`; helper `route_rows(items)` inserts straight into `"need_routing"` via `Repo.insert_all`):
- flag ON, one open question (`Server.Attention.ask/3`, as the existing tests do), no row: `grouped()` → `phone: [], uqbar: [%{key: k, route: "uqbar"}]`, `counts.uqbar == 1`, `counts.phone == 0`.
- row `passed_up` with recommendation "approve it": item in `phone` with `recommendation: "approve it"`, `route: "pass_up"`; `uqbar == []`.
- row `settled` (at = now): item in no surface; `settled == [%{key: k, why: "w"}]`; `counts.settled == 1`; row older than 24h: gone from `settled` too.
- row with `at` older than the item's `at`: ignored (item is in `uqbar`).
- seats/quota/tool_denied fixtures (reuse the ones already in needs_test): on `phone`, `recommendation: nil`, no row. `mention`/`rollout` fixtures: `route: "info"`, never in `uqbar`.
- flag OFF: question lands in `phone` (route "pass_up"), `uqbar == []`, `settled == []`, even with a `settled` row present.
- `Needs.list/0` unchanged: has no `route` key (assert `refute Map.has_key?(hd(Needs.list()), :route)`).
Code (`needs.ex`): `list/0` stays as is. Add private `routed/0` and rewrite `grouped/1`'s head:
```elixir
defp routed do
  items = list()
  rows = Map.new(Repo.all(from r in "need_routing", select: {r.key, %{state: r.state, why: r.why, rec: r.recommendation, at: type(r.at, :utc_datetime)}}))
  prune("need_routing", Map.new(rows, fn {k, r} -> {k, r.at} end), items)
  on? = Server.Flags.enabled?(:uqbar_routing)
  for item <- items do
    row = rows[item.key]
    row = row && DateTime.compare(row.at, item.at) != :lt && row
    Map.merge(item, %{route: route(pass_up_rule(item.kind), row && row.state, on?), recommendation: row && row.rec, why: row && row.why, settled_at: row && row.at})
  end
end

defp route(:info, _, _), do: "info"
defp route(:always, _, _), do: "pass_up"
defp route(_, _, false), do: "pass_up"
defp route(_, "passed_up", _), do: "pass_up"
defp route(_, "settled", _), do: "settled"
defp route(_, _, _), do: "uqbar"
```
(`prune/3`'s exact arity/shape: read it at `needs.ex` near `defp prune` and match; do not change it.) In `grouped/1` replace `items = list()` with:
```elixir
all_items = routed()
{settled, live} = Enum.split_with(all_items, &(&1.route == "settled"))
items = Enum.filter(live, &(&1.route in ~w(pass_up info)))
uqbar = Enum.filter(live, &(&1.route == "uqbar"))
digest = Enum.filter(settled, &DateTime.after?(&1.settled_at, DateTime.add(now, -@machine_hours * 3600, :second)))
```
then keep the existing heard/machine logic over `items`, and end with:
```elixir
groups = %{phone: ..., machine: machine, clipboard: ..., uqbar: uqbar, settled: digest}
Map.put(groups, :counts, Map.new(groups, fn {s, l} -> {s, length(l)} end))
```
Note `annotate/1` already strips nothing; `phone`/`clipboard` rows carry `recommendation` (nil for always). `settled` rows carry `why`.
Done: `needs_test.exs` green (new + all #326 tests).

## T3 — settle / pass_up / overrule  (`needs.ex`)
Tests first:
- `settle(k, "dup", "daneri")` → `{:error, :forbidden}`, no row; `pass_up(k, "w", "r", "daneri")` same.
- `settle("nope", "w", "uqbar")` → `{:error, :not_found}`.
- `settle(seats_key, "w", "uqbar")` and tool_denied key → `{:error, :always}`; mention → `{:error, :always}`.
- `settle(k, "dup of #12", "uqbar")` → `:ok`; item leaves `phone/machine/clipboard/uqbar`, in `settled` with `why`.
- `pass_up(k, "outward", "approve", "uqbar")` → `:ok`; item in `phone`/`clipboard` per its surface, with `recommendation`.
- `overrule(k)` after settle → `:ok`, item back in `uqbar` (not on any reaching surface); `overrule(k)` again → `{:error, :not_settled}`; overrule of a passed_up key → `{:error, :not_settled}`.
- calling settle twice upserts (state/why replaced, `at` refreshed).
Code:
```elixir
@doc "Uqbar's verdict: this one is handled without the operator. `by` is the caller's handle; only `uqbar`. …"
def settle(key, why, by), do: record(key, by, %{state: "settled", why: why, recommendation: nil})
def pass_up(key, why, recommendation, by),
  do: record(key, by, %{state: "passed_up", why: why, recommendation: recommendation})

@doc "The operator reverses a settle: the item returns to Uqbar's queue. `:ok` or `{:error, :not_settled}`."
def overrule(key) do
  case Repo.delete_all(from r in "need_routing", where: r.key == ^key and r.state == "settled") do
    {0, _} -> {:error, :not_settled}
    _ -> :ok
  end
end

defp record(_key, by, _row) when by != "uqbar", do: {:error, :forbidden}
defp record(key, _by, row) do
  case Enum.find(all(), &(&1.key == key)) do
    nil -> {:error, :not_found}
    %{kind: kind} ->
      if pass_up_rule(kind) in [:always, :info] do
        {:error, :always}
      else
        now = DateTime.truncate(DateTime.utc_now(), :second)
        Repo.insert_all("need_routing", [Map.put(row, :key, key) |> Map.put(:at, now)],
          on_conflict: {:replace, [:state, :why, :recommendation, :at]}, conflict_target: :key)
        :ok
      end
  end
end
```
(Arg order matches the spec's `settle/2`,`pass_up/2` modulo the trailing `by`; recommendation required non-empty for pass_up — return `{:error, :no_recommendation}` on `""`/nil, add a test.)
Done: needs_test green.

## T4 — `POST /api/office/needs/overrule`  (`server/lib/server/mcp/operator_api.ex`, its test)
Test first (the operator_api test file, copy the dismiss route test): POST `{"key"}` after a settle → 200; unsettled → 409 (reuse what `reply/3` does for `{:error, _}` — check, mirror dismiss); bad body → 400.
Edit: add `"overrule"` to the `when verb in [...]` guard at the dismiss/retire route; `result = case verb do "dismiss" -> …; "retire" -> …; "overrule" -> Server.Office.Needs.overrule(key) end`. Moduledoc list line: `POST /api/office/needs/overrule  Office.Needs.overrule {"key"} (a settled item goes back to Uqbar's queue)`; also amend the `GET /api/office/needs` line: `?by=surface` → `phone, machine, clipboard, uqbar, settled, counts`.
Done: that test file green.

## T5 — MCP tools `settle_need`, `pass_up_need`  (`server/lib/server/mcp/tools/operator_inbox.ex` or a sibling `needs.ex`, `endpoint.ex`, `profiles.ex`)
Test first (`server/test/server/mcp/tool_test.exs` style; build the frame the way the neighbouring tool tests do — `grep -n "Frame\|raw_claims" server/test/server/mcp/*_test.exs`): a frame whose `sub` is `daneri` calling `SettleNeed.execute(%{key:, why:}, frame)` → error reply containing "forbidden", no `need_routing` row; `sub: "uqbar"` → ok and one row; same pair for `PassUpNeed` (+ `recommendation`).
Code: two modules with `use Server.MCP.Tool`, schema fields `key`/`why` (+`recommendation`), `execute` does `Needs.settle(p.key, p.why, Identity.from_frame(frame).agent)` and maps `{:error, :forbidden}` etc. to `fail(frame, "…")` messages (`reply/3` handles `{:error, binary}`). Register in `endpoint.ex` after `operator_inbox`: `component(…SettleNeed, name: "settle_need")`, same for `pass_up_need`. Other seats' tool lists are NOT changed (refused, not hidden). In `profiles.ex` check whether Uqbar's `mcp: @tlon_mcp` allowlist is explicit (line ~321 lists `operator_inbox`): if Uqbar's list names tools, add both; if not, nothing.
Done: test green; `menard run check --in server`'s names gate passes.

## T6 — TUI data  (`office/tui/data.ts`, its test)
Test first (the file beside data.ts that tests `inboxOf`/needs; `ls office/tui/*test*`): payload with `uqbar:[a,b], settled:[c]` → `Needs.uqbar.length==2`, `.counts.uqbar==2`, `.counts.settled==1`; payload without them (old server) → both `[]`; `data.overrule("k")` POSTs `/api/office/needs/overrule` with `{key:"k"}` (mock like `hear`'s test).
Edit: `Need` gains `route?`, `recommendation?: string|null`, `why?: string|null`. `Needs = { items; phone; machine; clipboard; uqbar: Need[]; settled: Need[]; counts: Record<Surface | "uqbar" | "settled", number> }`; `inboxOf` takes `uqbar`/`settled` (default `[]`) and counts them; `items` stays the three reaching surfaces (the top bar and `d` etc. ignore uqbar). `noNeeds` + `main.ts:273` initial value gain the new fields. Add `export const overrule = (key: string) => post("/api/office/needs/overrule", { key })` next to the `hear` function (mirror its exact helper).
Done: office gate for data tests green (`mise run office:test` or the module's own task; `mise tasks | grep office`).

## T7 — TUI inbox  (`office/tui/main.ts` ~1672–1750, `keys.ts`)
Test first (where inbox rendering/keys are tested; `grep -rn "WAITING ON YOU" office --include=*test*`): given a Needs with one item in each group, the rendered rows are in order PHONE, MACHINE, CLIPBOARD, `with Uqbar: 1`; settled rows render under the machine with their `why` and `overrule`; the title still counts `counts.phone` only; pressing `o` on a settled row calls `data.overrule(row.key)`; a clipboard row with `recommendation` shows `tip: <rec>` line.
Edit: extend `order` (line ~1733) with `[...phone, ...machine, ...settled, ...clipboard, ...uqbar]` — settled sits with the machine as digest — tint `ROLE.body` for settled, `ROLE.inactive` for uqbar; detail line for settled: `settled by Uqbar · <why>`; for uqbar: `with Uqbar`. Section header `with Uqbar: N` only when `counts.uqbar > 0`. Bind `o` (keys.ts, follow how `d` dismiss is bound and gated: only on rows with `route==="settled"`/in `settled`) to `data.overrule(n.key)` then refresh needs. Recommendation: append to the clipboard/phone detail `tip: ${n.recommendation}` when set.
Done: office gate green + `drive-office` skill screenshot-in-text of the inbox with a fixture payload (attach to the thread).

## T8 — clipboard in the room  (`office/kit/draw.ts`, `main.ts:2078`)
Builder: `grep -n clipboard office/kit/draw.ts`. The room draws the rows it is handed (`Focus.clipboard`); the server now sends only passed-up/always rows in `bySurface.clipboard`, so (a) check the clipboard badge uses `counts.clipboard`/rows length not a recount of kinds, (b) draw the first row's recommendation as its tip where the clipboard already shows a row's text. Test first in the kit's draw test: a `ClipRow` with `recommendation` renders the tip text.
Done: kit tests green.

## T9 — docs, same PR
`Needs` moduledoc: add a "Routing" section with the pass-up table above, `route`, `need_routing`, and the three functions; update the phone/machine/clipboard prose where flag-on changes who sees it; `office/AGENTS.md` (and `docs/` page that names the inbox, `grep -rn "clipboard" docs office/AGENTS.md`): inbox order, `o` overrule, flag `uqbar_routing` shipped off, "keep it off until Uqbar's playbook lands" (spec's out-of-scope). Gate: `mise run check:names` clean.
Done: `menard run check --in server` ok; office and adapters module gates green; then advance.

## Handoff
Builder reads spec.md first; open question "gate check handle vs session kind" is settled by decision 1 above. Fetch from origin failed in my sandbox: confirm #326 (57b5597) is on origin/main before the final rebase.
