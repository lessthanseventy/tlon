# Plan — TICKETS column as an initiative → epic → ticket tree (#616)

Planned from main as it is (169c3e9 already has: initiatives in the column, summed progress, the group card via
`groupRows`, `kind: "epic"` acts). Left to build: **in-flight children**, an **expandable in-place tree** in the
column card, and the **whiteboard sticky** (one line per initiative + "N loose"). Check `mise run release:status`
first: if the live TUI still shows loose "ticket" rows for initiatives, the release lags main, not the code.

**Conflict:** tasks 3–5 touch `office/tui/main.ts` / `office/kit/types.ts` like #615's office slice. Land tasks 1–2
first (small, no conflict), build 3–5 only after #615's office slice lands (rebase if the other goes first).

Gates: server `~/projects/menard/bin/menard run test --in server <file>`; office `mise run office:check`
(unsandboxed; day/night tests need `OFFICE_TEST_HOUR=3` and `=15`). Each task = one commit, test first.

## Task 1 — server: in-flight children reach the snapshot
Why: `Server.Office.tickets/1` (`server/lib/server/office.ex:398`) drops every `doing` ticket, so a child that is on a
thread is invisible. Keep `doing` tickets that have an epic, and name their thread.

Test first, `server/test/server/office_test.exs` (follow its existing ticket fixtures): an epic with two children, one
started with `Server.Tickets.promote/2` into thread T. `Server.Office.snapshot` tickets contain the started child with
`status: "doing"`, `thread_id: T`; the unstarted child has `status: "todo"|"backlog"`, `thread_id: nil`. A loose `doing`
ticket (no epic) is still absent. Run: red (child missing).

Code (`office.ex`):
```elixir
defp tickets(ws_ids) do
  add_progress(
    for ws <- ws_ids, t <- Server.Tickets.open_in_workspace(ws), shown?(t, Server.Tickets.epic_of(t.id)) do
      %{id: t.id, workspace_id: ws, project_id: t.project_id, title: t.title, priority: t.priority,
        routed: t.status == "todo", kind: t.kind, status: t.status, epic_id: Server.Tickets.epic_of(t.id),
        thread_id: if(t.status == "doing", do: Server.Tickets.thread_of(t.id))}
    end, ws_ids)
end
# a started loose ticket is its thread's now; a started child stays on its epic's tree
defp shown?(t, epic_id), do: t.status != "doing" or t.kind != "ticket" or epic_id != nil
```
(compute `epic_of` once per ticket — bind it in the `for` with `epic_id = ...`). Add to `Server.Tickets`:
```elixir
@doc "The thread a ticket was promoted into, or nil."
def thread_of(ticket_id),
  do: Repo.one(from tt in TicketThread, where: tt.ticket_id == ^ticket_id and tt.kind == "promoted", select: tt.thread_id, limit: 1)
```
Done: the new test green, `menard run test --in server server/test/server/office_test.exs` ok.

## Task 2 — types: `status`, `thread_id` on `Ticket`
`office/kit/types.ts:35` — add `status?: string; thread_id?: number | null` to `Ticket` (one line; alone because it is
the conflict surface with #615). Test: `office/test/board.test.ts` gains a snapshot helper field use in Task 3, so this
commit's check is `mise run office:check` typechecks. Done: gate green.

## Task 3 — kit: pure `treeRows`
`office/kit/crew.ts`, beside `groupRows`. Test first in `office/test/board.test.ts` (use its `snap`/ticket helpers):
with initiative 585 → epics 586 (children 590 todo, 591 doing on thread 40) and loose ticket 7:
- `treeRows(a, new Set(), id => id)` → `[group 585 depth 0 closed, ticket 7 depth 0]` (collapsed: top level only)
- open `{585}` → 585, then 586 at depth 1 (closed), then 7
- open `{585,586}` → …586, 590 (depth 2), 591 (depth 2, `flight: 40`), 7
- `order` is applied per level (pass a reversing comparator, assert both levels reverse)
- `treeRows` rows carry `{ act, depth, group: boolean, open: boolean, title, flight?: number }`.

Code:
```ts
export type TreeRow = { act: Act; depth: number; group: boolean; open: boolean; title: string; flight?: number }

/** the TICKETS column as a tree: groups expand in place; `order` sorts each level on its own */
export function treeRows(a: Agents, open: Set<number>, order: <T extends { id: number }>(xs: T[]) => T[]): TreeRow[] {
  const out: TreeRow[] = []
  const walk = (tks: Ticket[], depth: number) => {
    for (const tk of order(tks)) {
      const g = isGroup(tk), isOpen = g && open.has(tk.id)
      out.push({ act: g ? { kind: "epic", id: tk.id } : { kind: "ticket", id: tk.id }, depth, group: g, open: isOpen,
        title: g ? groupTitle(a, tk) : tk.title, flight: tk.status === "doing" && tk.thread_id ? tk.thread_id : undefined })
      if (isOpen) walk(epicChildren(a, tk.id), depth + 1)
    }
  }
  walk((a.tickets as Ticket[]).filter((t) => t.epic_id == null), 0)
  return out
}
```
`groupTitle` should also say `· N in flight` when children carry `thread_id` (assert in the same test). Done:
`mise run office:check` green; only `board.test.ts` + `crew.ts` changed.

## Task 4 — TUI: the column card renders the tree  (after #615's office slice)
`office/tui/main.ts` `case "column"` (≈line 1286). For `mode.col === 0` build rows from `treeRows(a, expanded, arrangeLevel)`
where `expanded` is a module-level `Set<number>` (reset with the mode); other columns unchanged. Row = indent
`"  ".repeat(depth)` + glyph `▾`/`▸` for groups (a plain space for tickets) + `#id title`; an in-flight child is dim
`  ⚙ on #<thread>` and its `open` goes to `act({kind:"thread",tid})`.
Keys (`office/tui/keys.ts` ids, scope `card:column`): enter/space on a group toggles it in `expanded` and redraws with
the cursor kept on the same `ref`; enter on a ticket opens it as now; new `column.o` key `o` = "open card" opens
`{kind:"epic",id}` (the old enter behaviour). Update `office/test/ticket-back.test.ts` to press `o` where it opened a
group by enter, and add `office/test/column-tree.test.ts` (drive via the existing test harness used by
`ticket-back.test.ts`): enter on an initiative shows its epics indented; enter again hides them; enter on a ticket
opens `TICKET #id`; `o` on an epic opens `EPIC #id`.
Verify live with the `drive-office` skill: expand, collapse, `o`, back; screenshot rows.
Done: `mise run office:check` green + the drive transcript posted.

## Task 5 — whiteboard sticky
`office/kit/crew.ts`: `stickyItems(a): { text: string; act: Act }[]` — one line per initiative `"{title} d/t"`
(summed `progressOf`), then `"N loose"` (act: `{kind:"column", col:0}`) when any top-level non-group ticket exists;
loose epics (no initiative) get a line too. Test first in `board.test.ts` (3 loose + 2 initiatives → 3 lines, last
`"3 loose"`). Use it for column 0 in `office/rooms/wide.ts` (`whiteboard`, ≈line 787, in place of `col.items` for
c === 0) and `office/rooms/rail.ts` (≈line 169, the `Sticky` list for column 0); header count stays the ticket
count. Regenerate the affected golden frames (`rail.test.ts`, `board-hits.test.ts`, any `wide` snapshot) and eyeball
the diff. Done: `mise run office:check` green (also with `OFFICE_TEST_HOUR=3` and `15`).

## Out of scope
Server-side initiative progress (the kit sums epics already); new ticket kinds; reordering across levels.
