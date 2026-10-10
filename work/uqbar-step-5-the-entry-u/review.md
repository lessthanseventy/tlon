Reviewer on the same model as the builder (glm-5.2), as the review stage requires.

## Verdict: APPROVE

The gate from §7 step 5 — *U shows counts that match the board; a footnote key opens its thread* — holds. Re-ran `bun test test/entry.test.ts` → 5/5 green (22 expects); `tsc --noEmit` clean on entry.ts/crew.ts/main.ts (only the pre-existing `pngjs` devDep errors in untouched cli.ts/test/cli.test.ts); the verify gate ran `mise run check` green on the branch.

### What was checked

- **Counts can't disagree with the board.** `entryOf` builds `counts = Object.fromEntries(boardColumns(a, ctx).map(c => [c.name, c.items.length]))` on the same narrowed view (`viewOf(all, ws)`) and the same `boardCtx()` the board draws. The test deep-equals `e.counts` to a fresh `boardColumns` call, column for column (BUILD 2, REVIEW 3, DOING 1, TICKETS 1).
- **Footnotes are keys that open threads.** Every board item with `asks` (i.e. `needsYou`) and `act.kind === "thread"` becomes a footnote carrying `act:{kind:"thread",tid}`; pinned to #13 (awaiting qa) and #14 (a prompt). The TUI's `act()` dispatches each `Act`, and the new `{kind:"needs"}` (added to the union for the inbox footnote) now routes through `inbox()` — previously `act()` had no `case "needs"`, so it was a silent no-op. A genuine fix.
- **Pure / no state of its own.** `entryOf` is a read of its arguments; the `entry` mode in `detail()` calls it on the live `a/needs/feed` each render. Diary and shipped-today derive from `feed` filtered to `sameDay` (UTC); diary to `who === "uqbar"`. Both pinned.
- **Spec fidelity (§5).** Prose + stage×coworker pivot (counts + oldest-wait per cell), waiting-on-you, shipped today, known problems, and a diary of Uqbar's day; `esc` closes (back1). All present.

### Non-blocking follow-ups (filed as held tickets; none touch the gate)

1. **Pivot under-counts vs the board for unled stage threads.** `cellOf` counts only items where `it.who === cow`; an unled staged thread has `who:null` (boardColumns sets `who: r?.agent ?? th.lead ?? null`) and appears in no coworker row, so the pivot's stage total can be less than `counts[stage]` the prose reports. The test's "pivot stage totals match the board" invariant passes only because its `world()` has no unled stage threads — it papers over the edge. Either render an unowned/— row, or weaken that assertion to scoped-to-owned.

2. **Prose `works` includes SPEC+PLAN the sentence doesn't name.** `works = DOING+SPEC+PLAN+BUILD+REVIEW` but the sentence names only build/review/doing, so with populated SPEC/PLAN columns the figure won't add up. Either sum only the named stages or name all five.

3. **No trailing newline** on `kit/entry.ts` and `test/entry.test.ts` (sibling `crew.ts` has one). Cosmetic.

### Noted, not flagged

The "oldest wait per cell" uses the activity feed's `at` as a proxy for a stage-entered timestamp (threads carry none on the snapshot). otalora disclosed this on the thread; it renders as an age string and isn't test-pinned. Exactness is a server-side slice (a `stage_entered`/`created_at` field), separate from this one.