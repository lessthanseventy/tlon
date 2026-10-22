# Plan: what waits on Andrew, sorted by who acts (#167)

Spec: `spec.md` beside this. Assumptions (just to confirm, then confirmed against the tree):
- No `/api/office` blob carries needs today. The only route is `GET /api/office/needs` (`server/lib/server/mcp/operator_api.ex:201`), read by `office/tui/data.ts:114` (`needs()`). So "the office payload" = that route; its body becomes the grouped shape. `Needs.list/0` stays FLAT (alerts.ex:41 and mcp/tools/operator_inbox.ex:22 read it; they are untouched).
- "Top bar" = the header in `office/tui/main.ts` (~2033). "Red issues sign by the door" = `beacon()` in `office/kit/tiles/office.ts:146`, fed by `a.triage`. "Phone/machine" are new, small, pure kit pieces. `Pr_blocked/publish_failed/release_failed` are clipboard (provisional per spec).
- Gate: per task `~/projects/menard/bin/menard run test --in server <file>` (Elixir) / `cd office && bun test <file>`; last task `menard run check --in server` + `bun test` in office. Edit Elixir with menard verbs. A seat does NOT run `mise run check`.
- One small PR. Rebase onto origin/main before opening (Needs is hot). #557 touches the same top bar: whoever lands second rebases.

Order matters: 1→2→3 (server), 4→5→6→7 (office). Each task = one commit.

## Task 1 — `Needs.kinds/0` + `Needs.surface/1` (pure, no catch-all)
Files: `server/lib/server/office/needs.ex`, `server/test/server/office/needs_test.exs`.
1. Test first (append to needs_test.exs):
```elixir
describe "surface/1" do
  test "every kind has a surface" do
    for k <- Needs.kinds(), do: assert(Needs.surface(k) in ~w(phone machine clipboard))
  end

  test "the table" do
    phone = ~w(gate question dialog ask seats quota no_seat tool_denied)
    machine = ~w(mention rollout)
    clip = ~w(issue stalled verify_failed pr_blocked publish_failed release_failed job_failed stranded)
    for k <- phone, do: assert(Needs.surface(k) == "phone")
    for k <- machine, do: assert(Needs.surface(k) == "machine")
    for k <- clip, do: assert(Needs.surface(k) == "clipboard")
    assert Enum.sort(Needs.kinds()) == Enum.sort(phone ++ machine ++ clip)
  end

  test "an unlisted kind is not routed" do
    assert_raise FunctionClauseError, fn -> Needs.surface("brand_new") end
  end
end
```
2. Code (after `list/0`, with `@doc`s; NO catch-all clause):
```elixir
@kinds ~w(gate question dialog ask seats quota no_seat tool_denied mention rollout issue stalled verify_failed pr_blocked publish_failed release_failed job_failed stranded)
@doc "Every kind the list can hold — each has a surface (`surface/1`)."
def kinds, do: @kinds

@doc "Where a kind is answered: phone (an answer is owed), machine (information), clipboard (the crew owns it)."
def surface(kind) when kind in ~w(gate question dialog ask seats quota no_seat tool_denied), do: "phone"
def surface(kind) when kind in ~w(mention rollout), do: "machine"
def surface(kind) when kind in ~w(issue stalled verify_failed pr_blocked publish_failed release_failed job_failed stranded), do: "clipboard"
```
Done: `menard run test --in server server/test/server/office/needs_test.exs` green.

## Task 2 — every emitted item carries `surface` (+ clipboard `owner`, `tracking`)
Files: `needs.ex`, `needs_test.exs`.
1. Test first: using the existing fixtures in needs_test.exs for each emitter (gate, question, dialog, ask, seats, quota, no_seat, tool_denied, mention, rollout, issue, stalled, verify_failed, pr_blocked, publish_failed, release_failed, job_failed, stranded — reuse the existing per-kind tests' setup; add one `test "list/0 items all carry a surface"` that, in each existing kind test, also asserts `item.surface == Needs.surface(item.kind)`; simplest: a helper `assert_surfaced(items)` called from those tests). Plus a clipboard test: an `issue` item on a workline thread has `tracking == thread.slug` (or `"#<ticket id>"` when `i.ticket_id`) and `owner` == the thread's lead handle (look up as `Server.Maintain`/staffing does for lead — grep `lead` in `server/lib/server/workline.ex`/`staffing.ex`; nil when none).
2. Code: `item/6` (needs.ex:405) is the single constructor — add `surface: Server.Office.Needs.surface(kind)` to its base map (kind raises if unlisted: the compile-time-ish guard). The few items built OUTSIDE `item/6` (`seats` ~194, `job_failed` ~227, `rollout` ~345, `stranded` ~367, `quota_item` ~537, release/other maps) get `surface: surface("<kind>")` the same way. Clipboard items get `owner` and `tracking` in `all/0`: `Enum.map(&annotate/1)` where `annotate(%{surface: "clipboard"} = i)` merges `owner:` (thread lead, nil if no thread) and `tracking:` (thread slug, else ticket id string, else nil); other surfaces pass through. Keep `level` untouched.
Done: needs_test green.

## Task 3 — grouped read + `heard` record (machine leaves once heard / after 24h)
Files: new `server/priv/repo/migrations/20261021000000_need_heard.exs` (copy need_dismissal's shape: table `need_heard`, `key` string pk, `at` utc_datetime), `needs.ex`, `server/lib/server/mcp/operator_api.ex`, `needs_test.exs`.
1. Tests first:
```elixir
test "2026-10-10 state: issues 13-16 + two mentions => phone 0, machine 2, clipboard 4" # build 4 open issues + 2 mentions via existing helpers; assert Needs.grouped().counts == %{phone: 0, machine: 2, clipboard: 4}
test "a machine item leaves once heard" # Needs.hear([key]) then grouped().machine == []; clipboard unaffected
test "a machine item older than 24h is not on the machine" # mention @13h..: mentions already cap at 12h; use a rollout note with at = 25h ago
test "grouped/0 shape" # keys phone/machine/clipboard/counts; counts match lengths
```
2. Code: `grouped/0` = `list/0` → `Enum.group_by(& &1.surface)`, machine filtered by `need_heard` rows and `at > now-24h`, `counts` from the lists; `hear(keys)` upserts into `need_heard` (mirror `remember/1`), `prune` `need_heard` rows whose key is gone (mirror `prune/2`). `list/0` stays flat and unfiltered by heard (alerts/inbox tool unaffected).
3. `operator_api.ex`: `GET /office/needs` → `json(conn, 200, Server.Office.Needs.grouped())`; add `POST /office/needs/heard {"keys": [...]}` → `Needs.hear/1`; update the route doc block at the file head (lines ~20-23).
Done: needs_test + the operator_api test (grep `office/needs` in `server/test`; update any that decode the old list) green.

## Task 4 — TUI data reads the grouped shape
Files: `office/tui/data.ts`, `office/test/data.test.ts`.
1. Test first: `needs()` given `{phone:[a], machine:[b], clipboard:[c], counts:{...}}` returns `{items:[a,b,c], phone, machine, clipboard, counts}`; a failed call returns the last good value (existing contract at data.ts:113).
2. Code: `Need` gains `surface: "phone"|"machine"|"clipboard"`, `owner?: string|null`, `tracking?: string|null`. `needs()` returns that object; add `hear = (keys: string[]) => write("marking heard", "/office/needs/heard", { keys }, () => "heard")`.
3. `main.ts`: `let needs: data.Need[]` stays the flat array (`= r.items`) so boardCtx/mailbox/entry callers don't change; add `let counts`. Update the one assignment at ~439.
Done: `cd office && bun test test/data.test.ts` + `bunx tsc --noEmit`.

## Task 5 — top bar: one phone count, rings while N>0
Files: new `office/kit/surfaces.ts`, `office/test/surfaces.test.ts`, `office/tui/main.ts` (header ~2033).
1. Test first: `phoneBar({phone:0})` → `null`; `phoneBar({phone:3})` → `{ text: "☎ 3 waiting on you", ringing: true }`; `ringFrame(tick, true)` alternates ≥2 distinct glyph frames (e.g. "☎"/"☏") so ringing is never colour alone; `ringFrame(_, false)` constant.
2. Code: those two pure functions in `surfaces.ts`. Header: replace the `blocking`/`deciding` badges and the `(i)` hint with one segment from `phoneBar(counts)` (`go: inbox`, `ROLE.attention` bold, glyph from `ringFrame`); nothing for machine/clipboard in the bar. Remove now-unused `blocking`/`deciding` locals at ~2033.
Done: surfaces.test green; `main.ts` typechecks.

## Task 6 — the machine's blinking light + the clipboard replacing the beacon
Files: `office/kit/surfaces.ts` (+draw fns), `office/kit/tiles/office.ts` (beacon ~146), `office/rooms/wide.ts` (feed counts; ~299 reads `a.triage` for the erratum — leave it), `office/test/surfaces.test.ts`, `office/test/golden.json` (regen via the golden script already in `office/test/golden.ts`).
1. Test first (render): `drawMachine(sc, x, y, n)` with n>0 paints differently on tick 0 vs the blink-off tick, n=0 never blinks and paints the same on both ticks (Scene pattern from `mailbox.test.ts`); label `"N new messages"` is the hit tip. `drawClipboard(sc, x, y, rows)` with rows paints differently from empty; tip lists `owner · tracking · title` per row. Golden: a frame with phone 2 / machine 1 renders a stable PNG hash.
2. Code: `drawMachine` (light blinks while n>0, `${n} new messages` overhead text, hit → `act: {kind:"machine"}`), `drawClipboard` (replaces `beacon()` at the door: same position `x = OFF_W - 4`; hit → `act: {kind:"clipboard"}`; count is `counts.clipboard`, text "N on the clipboard"). Add the two `Act` kinds to `office/kit/crew.ts:31` union. Wire the counts into the office scene the way `stuck` reaches `beacon()` today (follow `a.triage` → scene call in `tiles/office.ts`).  Place the machine beside the in-tray (`TRAY` const).
Done: `bun test` of surfaces + golden green; delete beacon-only code that is now unreferenced.

## Task 7 — inbox (`i`) groups by surface; opening the machine marks it heard; docs
Files: `office/tui/main.ts` (case "needs" ~1659, "decide" ~1721), `office/kit/entry.ts` (line 81 section uses `needs`; leave unless it reads wrong), `office/tui/keys.ts` if a key label changes, `office/test/` a small `inbox-surfaces.test.ts` for the pure grouping, `server/lib/server/office/needs.ex` @moduledoc, `office/AGENTS.md` if it names the header/beacon.
1. Test first: pure `bySurface(items)` (put in `surfaces.ts`) orders phone (blocking before decide, then oldest) → machine → clipboard; clipboard rows format `owner · tracking`.
2. Code: inbox sections PHONE / MACHINE / CLIPBOARD replacing BLOCKING / TO DECIDE (titles use `counts`); clipboard rows show `n.owner ?? "nobody"` and `n.tracking ?? "untracked"`; the `decide` card order = phone first. Opening the `machine` act or the inbox's MACHINE section calls `data.hear(machineKeys)`. `NEED_KIND`/`NEED_TONE` maps unchanged.
3. Moduledoc: rewrite the blocking/decide taxonomy to the three surfaces + the table; keep `level` documented as order-within-surface. Mention `grouped/0`, `hear/1`, `need_heard`.
Done: `bun test` (office) green.

## Task 8 — gate and hand off
`~/projects/menard/bin/menard run check --in server` and `cd office && bun test && bunx tsc --noEmit`; `git rebase origin/main`; re-run both; commit; `advance_stage`. Verify's full `mise run check` is the server's job.

## Risks to watch
- `item/6` raising on an unlisted kind breaks any emitter added on main meanwhile: after the rebase, grep `item("` in needs.ex for new kinds and add rows (spec's rule).
- Existing tests that decode `GET /office/needs` as a list, and office tests that build `Need` objects without `surface` — fix their fixtures, don't loosen the type.
- Old servers: the TUI's `needs()` should treat a bare array as `items` (one-line guard) so a stale server doesn't blank the bar.
