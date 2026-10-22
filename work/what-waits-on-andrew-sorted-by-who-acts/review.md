# Review — what waits on Andrew, sorted by who acts (#167, thread #326)

**Verdict: APPROVE**

No free reviewer is at the builder's grade (greybeard); tzinacan leads this review.

Spec-compliant, surgical, fully gated: `menard run check --in server` 2008/0 after rebase onto origin/main 0a5b7db; office 813/0, `tsc --noEmit` clean, golden rehashed.

- `Needs.surface/1` has no catch-all clause (raises on an unlisted kind); `kinds/0` lists all 18 kinds and the test pins the table. A new kind cannot reach the list unrouted.
- Every emitted item carries `surface` via the single `annotate/1` pass; clipboard rows also carry `owner` (thread lead) and `tracking` (workline slug, else `#ticket`), fetched in one query. `level` is untouched. The `item/6`-outside items (seats, job_failed, rollout, stranded, quota) are surfaced too.
- `grouped/0` = `list/0` grouped by surface, the machine further filtered by `need_heard` and a 24h age (`@machine_hours 24`); `hear/1` upserts into the new `need_heard` table; `prune/3` is generalised over both tables. `list/0` stays flat and unfiltered, so alerts and the inbox tool are untouched. The 24h seam is exercised (mention + a future `now`), and the 24h bound is the one that bites for `rollout` notes, which have no emitter-side cap.
- Routes: `GET /office/needs?by=surface` serves the grouped body; bare `GET /office/needs` still returns the flat list (adapter and stubs read an array); `POST /office/needs/heard` is wired and tested, and sits before the `verb in ["dismiss","retire"]` clause with no conflict. Doctor test adds `need_heard` to the tables check.
- Office: top bar shows one ringing count (`phoneBar` + `ringFrame`, ☎/☏ so the ring is never colour alone); the room gets `drawMachine` (blinks while unheard) and `drawClipboard` replacing `beacon()` at the same door position; the inbox (`i`) groups PHONE/MACHINE/CLIPBOARD via `inboxSections`; `tellNews` rings only for new phone items; `hearMachine` marks the machine's keys heard. The retained `beacon` Act kind is still pushed by `kit/entry.ts:61,84`, so it is not dead.
- Moduledoc and `office/AGENTS.md` rewritten to match.

No blocking defect found.

## Follow-ups (non-blocking, open)

**1. The stale-server degradation comment inverts the behaviour.** `office/tui/data.ts` `needs()` says "a server with only the flat list is grouped by each item's surface, none on the phone." The code does the opposite: `(n.surface ?? "phone")` puts every bare item on the phone, so the bar rings for *everything* during a TUI-newer-than-server window. The companion test asserts `expect(r.phone).toEqual([bare])` — code and assertion are right; only the comment and the test's title ("no surface on the phone") describe the wrong behaviour. Fix the comment to match the code (bare items default to the phone so nothing hides) and retitle the test. Prose-only, no runtime effect — does not block.

**2. A clipboard row with no workspace shows on every workspace's room clipboard.** `main.ts` renders `bySurface.clipboard.filter((n) => n.workspace_id == null || n.workspace_id === ws)`, so a nil-`workspace_id` clipboard item (a stranded worktree with no thread is the main case) appears in every workspace's room. The inbox count uses the unfiltered cross-workspace total, so the room and the inbox already disagree on scope here; worth a small decision on whether nil-scope clipboard rows belong to a specific workspace or to none. Cosmetic edge; does not block.