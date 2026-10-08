# Epics and initiatives — the backlog stops being one flat list

**Status:** approved by Andrew 2026-10-08 ("yeah do it"). Initiatives start as a label; they get
their own level only if a label stops being enough.

## 1 · The problem

Machine's backlog is 37 tickets in one list. The only grouping is labels, and the only ordering
is intake's (`Server.Intake.next/1`): highest priority, then the **newest** ticket. So whatever was
filed last jumps the queue, and a six-step design started yesterday waits behind a one-liner filed
an hour ago. Neither Andrew nor the board can tell "Toy: 2 of 12 done" from a list of titles.

The pieces are mostly there. `Server.TicketLink` has a `parent` kind that nothing uses. Every
group of work already has a design doc and a label (`uqbar`, `toy`, `souls`, `talk`). Step
order is expressed with `blocks` links.

The cockpit plan (ficciones, 2026-08-30) ruled out "epics/sprints/story-points/workflow
ceremony". This keeps that: no sprints, no points, no workflow states beyond the four a ticket
has. An epic is a ticket that holds other tickets.

## 2 · The shape

| Level | What it is | Example |
|---|---|---|
| **Initiative** | a label on epics, naming a goal across several designs | `kids`, `office-life`, `engine` |
| **Epic** | a ticket of `kind: "epic"`, its design doc in the body, its children tied by `parent` links | "Toy" (office-as-a-toy-design.md) |
| **Ticket** | as today, with at most one parent epic | #52 sandbox mode |

**The law:**

- **An epic is never work.** Intake never routes it, `start_thread` refuses it, and it never
  becomes a workline. Its work is its children.
- **An epic's status is derived:** `backlog` while no child has started, `doing` once one has,
  `done` when every child is done (stamped by the server when the last one closes; a child
  reopened or added sends it back to `doing`).
- **Parent direction:** `epic parent child`, stored once as `from = epic, to = child`, read both
  ways like `blocks`. A ticket has at most one parent, and an epic has no parent (one level of
  nesting). Both are refused as a changeset.
- **Priority flows down:** a child's effective priority is the higher of its own and its epic's.
  Setting an epic `high` moves its whole chain up.
- **Finish what's started:** among tickets of equal effective priority, intake prefers the child
  of an epic that is already `doing`. Within one epic it takes the **lowest** `sort` first (step
  order), not the newest. Loose tickets keep today's newest-first order.

## 3 · Surfaces

- **Board** (`Server.Board`, the office's ticket data): the backlog groups by epic. Each epic is
  one row with progress (`done/total`), its effective priority and its next free child (unblocked,
  not held). Children appear under it when it is opened. Tickets with no epic sit under
  "loose". Machine's 37 tickets become about 8 rows.
- **Office:** the tickets screen (`t`) and the crew board's TICKETS column show epics, not
  children: `Toy 2/13 → #52 sandbox mode`. `enter` on an epic opens its children; the ticket card
  shows its epic.
- **Filing:** `tlon-cli epic-new <ws> <title> [body…]`, `tlon-cli epic-add <epic> <ticket…>`, and
  the MCP ticket tools take an optional `epic_id`, so the manager files a design's steps straight
  into its epic.
- **Initiative:** a label on an epic. The board can group epics by it later; v1 only shows it on
  the epic's row.

## 4 · The epics today (the backfill)

| Initiative | Epic | Design | Children |
|---|---|---|---|
| `kids` | **Toy** | `2026-10-08-office-as-a-toy-design.md` | #52–59, #65–69 |
| `office-life` | **Uqbar** | `2026-10-08-uqbar-design.md` | #47–51 |
| `office-life` | **Souls** | `2026-10-08-souls-design.md` | #60–64 |
| `office-life` | **Talk** | `2026-10-08-office-talk-design.md` | #70–73 |
| `office-life` | **Home and whimsy** | `2026-10-06-home-space-and-dollhouse-design.md` | #27, #28, #32–36, #41–43 |
| `engine` | **Engine holes** | — | #74, #75 |

Left loose: #46 (Andrew's GitHub profile) and #76 (Crew screen sort/filter).

## 5 · Steps

| # | Step | Check |
|---|---|---|
| 1 | **Server:** `kind` on ticket (migration, `ticket`/`epic`, DB-CHECK'd); the parent law (one parent, no nested epics); derived epic status; intake skips epics and orders by effective priority, started epics first, step order within an epic | tests: intake never routes an epic; a child inherits a `high` epic; within an epic the lowest `sort` goes first; the last child done closes the epic; a second parent and an epic-under-epic are refused |
| 2 | **Filing and data:** `epic-new` / `epic-add` in `tlon-cli`, `epic_id` on the MCP ticket tools, the board payload carries epics with progress and their next free child | tests: the board groups children under their epic with the right `done/total`; `epic-add` refuses a second parent |
| 3 | **Office:** the tickets screen and the crew board's TICKETS column show epic rows; `enter` opens an epic; the ticket card names its epic | test: the tickets screen renders one row per epic plus "loose"; drive-office shows `Toy n/13` |
| 4 | **Backfill** (uqbar, no code): create the six epics in §4, tie their children, label the initiatives | `tlon-cli` board read shows the six epics with the right counts and nothing but #46 and #76 loose |

Step 1 comes first. Steps 2 and 4 follow it, and step 3 follows step 2. When step 1 lands,
`Server.Ticket`'s moduledoc stops saying "no epics".
