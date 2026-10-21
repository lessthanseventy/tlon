# Review — cast editor (the god view), work/cast-editor-the-god-view-spec

No free reviewer was at the builder's grade (greybeard), so tzinacan (Claude) leads this review.

**Verdict: approve.**

The build is spec-compliant, surgical and well-tested. T3 (the `seatActions` split into
`pickModel`/`pickPersona`/`unseatAsk`) is behaviour-preserving — the seat card's keys route
through the same bodies, only lifted. The two new modules are pure and unit-tested; the drive
test (`cast-view.test.ts`) runs the real TUI against a stub server and exercises every field —
open, reroll, unseat (n sends nothing, y the DELETE), the read-only hint, the look reroll
leaving bo's entry alone, and the soul file made once and never overwritten. Sandbox isolation
is proven: a grade ⏎ in `--sandbox` lands in `$TMPDIR/tlon-sandbox/cast.json` and the
operator's config dir stays empty (`cast-sandbox.test.ts`). Gates green (office:check 0 fail /
800, `mise run check` exit 0, verify evidence recorded).

The `hall.ts` change (`BLANK_SOUL` extracted) is an exact extraction — `roll()`'s `soul` field
is byte-for-byte unchanged. Keys: `` ` `` opens cast, `}` tabs (same verb "next group" as crew,
no collision), ←/→ the lit field, `y` rerolls, `-` unseats; all pass `keys.test`.

## Follow-ups (non-blocking)

1. **y on voice is a silent no-op.** The reroll key's label is "reroll the lit field", but on the
   voice cell it does nothing — voice does have a reroll (server persona). Reroll is reachable via
   ⏎ → persona picker → "draw a new one", but `y` should wire to `data.persona(w, id, true)`, or
   the key should hide/relabel when the lit field has no reroll (soul and model have none by
   design).
2. **Sandbox unseat still asks.** Spec §3 says sandbox skips the confirm and the toy answers
   locally; `unseatAsk` always runs `ask2`, so `-` in the toy asks. Consistent with the existing
   seat card (which also asks), but a spec deviation. Minor — one y/n in the toy.
3. **No bracket highlight on the name column.** The name cell is rendered separately and never
   bracketed, so with `castCol` 0 (name lit) the `[...]` cue is absent. The title bar names the
   field so it stays legible; the cue just skips that one column.
4. **pr.md is not committed.** The build stage asked for `work/cast-editor-the-god-view-spec/pr.md`;
   the builder noted it's owed. Needs to land before the merge gate publishes the PR.