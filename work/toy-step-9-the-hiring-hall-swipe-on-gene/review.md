# Review — toy step 9, the hiring hall (thread 257), round 2

**Verdict: request_changes.** All three blocking findings of round 1 are fixed (pr.md committed; hall view, keys, sandbox hire built; `Overrides.parts` with a test), and both follow-ups landed (`cleanLocks`, pile dedupe). Two new correctness bugs in the turn logic, both reproduced with a script against `kit/hall.ts`, both one-line fixes; they break spec §3 on the exact key path pr.md demonstrates (`h ← ← ↑ space →`).

## Blocking

1. **The maybe pile shows a different name than the card did (spec §3 "a pile entry always re-renders identically").** `maybe` stores `{seed, overrides}` without the name; the pile view renders it via `candidateOf(..., hallCtx())`, whose `taken` already contains that entry's own rolled name (from `takenNames`), so `roll` picks the next free name. Repro from an empty hall with bench `["funes"]`: card showed `tertius`, pile list shows `carlos`. Fix: bake the shown name into the pile entry (also makes `takenNames` cheap and stable when the bench changes):
   ```ts
   export const maybe = (h: Hall, o: Ctx): Hall => {
     const name = candidateOf(h, o).name
     return pass({ ...h, pile: pushPile(h.pile, { seed: h.seed, overrides: { ...h.overrides, name } }) }, o)
   }
   ```
   Test: after `maybe`, `candidateOf` of the pile entry with the full ctx has the name the card showed.

2. **Hire with the name locked leaves the next card wearing the hired name (spec §3 "minus names already on any bench").** `pass` bakes `cur.name` into the overrides whenever `name` is locked, and the override is applied after `roll`'s taken-check. Repro: lock name, hire `tertius` → next card is `tertius`, who is now on the bench. Pressing → again: `world.hire` silently no-ops, `saveLook` overwrites the hired person's look with the new roll, and the status still says "hired tertius". (`roll`'s own "a locked name since taken re-rolls" branch never runs from the app, since `candidateOf` passes no `prev`.) Fix, kit + caller:
   ```ts
   // kit/hall.ts, pass(): never bake a name that is taken
   for (const f of h.locks.fields ?? []) if (!(f === "name" && o.taken.includes(cur.name))) o2[f] = cur[f]
   ```
   ```ts
   // tui/main.ts, hallHire(): refuse a taken name, and pass with the hire counted as taken (all.bench is stale until refresh)
   const ctx = hallCtx()
   if (ctx.taken.includes(c.name)) { status = `${c.name} is already on the bench — unlock or edit the name`; return draw() }
   …
   hallSet(pass(hall, { ...ctx, taken: [...ctx.taken, c.name] }))
   ```
   Test: `pass` with `fields: ["name"]` and the current name in `taken` yields a candidate whose name is not in `taken`.

## Verified
- Read the full branch diff (`git diff origin/main...HEAD`) and the round-1 delta (`9757f79..HEAD`).
- Key dispatch: a card's own actions win before the global `up`/`left`/`right` handlers (`onKey`, main.ts ~1901), so ←/↑/→/space mean what the hall says; tab/backtab are intercepted for row stepping before the crew walk. `toyKey` runs first, but its play keys don't include the hall's.
- `cd office && bun test test/hall.test.ts test/hall-view.test.ts test/sandbox.test.ts`: 36 pass, 0 fail (recorded).
- Sandbox dir move (`$TMPDIR/tlon-sandbox`) is documented in AGENTS.md; `TLON_*` still win.
- Commit trailers name the model that wrote them.

## Non-blocking (follow-ups, filed)
- `roll`'s `prev`/lock branch is unreachable from the app; locks are kept by `pass` baking overrides. One mechanism, not two.
- Spec §2 `e` (edit the look / soul from the hall) has no plan task and is not built; `s` is task 7 (blocked). Needs a home.
- `hall-pile` `x` re-implements `dropPile` inline.

## Still out of this branch, as agreed
Plan tasks 1, 2, 6, 7 wait on souls-step-2 (`Server.Soul`); the office's → says so and seats nobody. #65 stays open for that half.