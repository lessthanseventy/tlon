# Spec: Uqbar routing — needs reach Andrew only through Uqbar (#578, from yu's respec of #167)

Builds on #326 (`Needs.surface/1`, `grouped/1`, `need_heard`, on origin/main as 57b5597). #326 is this spec's flag-off case: with `uqbar_routing` off, behaviour is exactly #326's.

## Rule
Uqbar is the first stop for everything that would reach Andrew. An item reaches him only when Uqbar passes it up, or when its kind always passes up. A daily digest lists what Uqbar settled; Andrew can overrule it. `mention` and `rollout` are information: never routed.

## `pass_up` column (a pure function of kind, `Needs.pass_up_rule/1`, no catch-all)
| kinds | passes up |
|---|---|
| seats, quota, **tool_denied** | always (tool_denied widens a permission: operator ruling #12088) |
| gate, question, dialog, ask, no_seat | only if irreversible, outward, costly, needs a host command, or is an `auto_land_risk` gate |
| issue, stalled, verify_failed, job_failed, stranded | only if irreversible or needs a host command |
| pr_blocked, publish_failed, release_failed | only if it needs a host command |
| mention, rollout | `:info` — never routed |

Rules are `:always | {:when, [reasons]} | :info`. `Needs.kinds/0` stays the single list; a test fails if a kind lacks a rule.

## Model
- Each item gains `route`: `"uqbar"` (awaiting Uqbar) | `"pass_up"` | `"info"`.
- Table `need_routing` (migration): `key` string PK, `state` string (`settled`|`passed_up`), `why` text, `recommendation` text null, `at` utc_datetime. Keyed by item key like `need_dismissal`; pruned when the item leaves `all()`; a newer item under the same key is a new item (row's `at` older than item `at` → ignored).
- Route of an item: kind `:info` → info; `:always` → pass_up; row `passed_up` → pass_up; row `settled` → settled (leaves every surface, stays in the digest 24h); else conditional kind → "uqbar".
- API (`Server.Office.Needs`):
  - `settle(key, why)` and `pass_up(key, why, recommendation)`: **callable by Uqbar's seat only**; `{:error, :forbidden}` otherwise, `{:error, :not_found}` for an unknown key, `{:error, :always}` for an always/info kind (settling a seats/quota/tool_denied item is refused).
  - `overrule(key)`: deletes the settled row (mirrors `need_dismissal`); the item goes back into Uqbar's queue (route "uqbar"), not to Andrew. Operator-callable. `{:error, :not_settled}` otherwise.
- **Unchanged:** `Needs.kinds/0`, `Needs.surface/1` (where an item lands if it reaches Andrew), the machine's `hear/1`, and `Needs.list/0` (flat, unrouted). The server never infers the "if" from an item's text: the route comes only from Uqbar's recorded verdict or the always column.
- Seat-only gate: the MCP tool checks the caller's registered handle is `uqbar` (same mechanism the other seat-scoped tools use; builder: find it in `Server.MCP.Tool` and reuse it, do not invent a second).

## Flag `uqbar_routing` (`Server.Flags`, shipped OFF)
Off: every conditional kind routes as `pass_up` (== #326's behaviour; no `uqbar` group, no digest). On: as above. Off is the default so the merge changes nothing until the operator flips it.

## Payload
`GET /api/office/needs?by=surface` returns `{phone, machine, clipboard, uqbar, settled, counts}`:
- `phone`, `clipboard`: only passed-up and always items, each with `recommendation` (null for always-kinds).
- `uqbar`: items awaiting Uqbar. `settled`: settled in the last 24h with `why`. `counts` gains `uqbar` and `settled`.
- The top bar reads `counts.phone` only; the `uqbar` group is NOT counted there. `Needs.list/0` stays the flat, unrouted list.
- Same payload when the flag is off, with `uqbar: []`, `settled: []`.

## Surfaces
- TUI inbox (`office/tui/data.ts`, `main.ts`, `keys.ts`): sections PHONE, MACHINE, CLIPBOARD, then "with Uqbar: N" (not in the top bar count). The digest rows (settled, with `why`) sit on the machine, with an overrule key (`o`) calling `data.overrule` → `POST /api/office/needs/overrule {"key"}`. Clipboard rows show the recommendation tip. `Needs` type gains `uqbar`, `settled`.
- Clipboard in the room (`office/kit/draw.ts`) draws `counts.clipboard`.
- MCP tools `settle_need`, `pass_up_need` (Uqbar only; hidden from other seats' tool lists) and the `POST /api/office/needs/overrule` route; `operator_api.ex` moduledoc lists it.

## Migration
`need_routing` is a new table: additive, no backfill. Rollback = drop table; the flag off makes it unread.

## Done when
- Tests, red first. T3 (`Needs`), flag on:
  - the 2026-10-10 state with no rows gives phone 0, machine 2, clipboard 0, uqbar 4;
  - after `pass_up` on all four issues, clipboard is 4;
  - seats, quota and tool_denied sit on the phone with no row;
  - `settle` removes the item from every surface and puts it in `settled`; `overrule` brings it back to uqbar;
  - settle of an always-kind is refused; a newer item under a settled key is routed afresh; mention/rollout never routed; the rule table covers every kind.
- T7 (TUI): section order; digest rows on the machine; the overrule key calls `data.overrule`.
- T9: a coworker's `settle_need`/`pass_up_need` is refused; Uqbar's call lands a `need_routing` row.
- T10: flag off routes every conditional kind as `pass_up` (today's behaviour); payload has `uqbar: []`, `settled: []`.
- Moduledocs of `Needs` (including the pass-up table), `operator_api.ex` and the office `AGENTS.md`/docs updated in the same change.
- `mise run check` green (via `menard run check --in server` and the office/adapters gates).

## Out of scope (later thread)
Uqbar's judgement: its playbook, the prompt that calls settle/pass_up, and the digest-writing job. Until then with the flag on, nothing settles, so every conditional item waits in "with Uqbar" — keep the flag off until that lands.

## Open
- The seat-only gate's exact check (handle vs session kind) — builder confirms from the existing seat-scoped tools before writing the red test.
- Source of record: #11842 (read by hronir, who supplied its test list and unchanged-parts, #12146) together with ticket #578. Where this spec differs from #11842, #11842 wins.
