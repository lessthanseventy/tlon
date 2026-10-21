No free reviewer was at the builder's grade (greybeard), so tzinacan (Ollama, glm-5.2) leads this review.

**Verdict: approve.**

This round exists only because the merge queue's batched landing stacked #319's unmerged commits under our branch and bounced it back (fault #552, high). hronir rebased `--onto origin/main 8235f2f`, dropping the 5 foreign commits and keeping our 16 patches intact. `git range-diff f7888c5..HEAD` (code paths only) shows every one of the 16 cast-editor patches as `=` — identical subject, body and diff. No #319 wake-mod commit is in our branch. So the code under review is byte-for-byte the code I approved at f7888c5; only the base moved.

The verify gate agrees: `mise run check` exit 0 (recorded at e4496cc), office:check 802/0, and the workline artifact check passed. Nothing was committed after the last review, so there is nothing new to find.

My prior round's approval stands for the substance: `cast.ts` is pure and unit-tested, the `seatActions` split into `pickModel`/`pickPersona`/`unseatAsk` is behaviour-preserving, sandbox isolation is proven (`cast-sandbox.test.ts`), the reopen regression is pinned (`cast-view.test.ts` at 775889f), and every key passes `keys.test`. The pr.md follow-up is dropped — `Server.Workline.Publish.body/3` falls back to the spec/plan heading when pr.md is absent (publish.ex:236).

## Follow-ups (non-blocking, still open)

1. **y is a silent no-op on fields with no reroll.** `reroll` (main.ts:1886) wires only look, grade and specialty; on voice, soul, model, name and archetype the `y` key fires and does nothing. office/AGENTS.md scopes `y` to "rerolls look, grade or specialty", so the behaviour is documented — but the key still binds on every lit cell. Could hide or relabel `y` when the lit field has no reroll.
2. **Sandbox unseat still asks.** `unseatAsk` always runs `ask2`, so `-` in the toy prompts y/n. Spec §3 says sandbox skips the confirm and the toy answers locally. Minor — one y/n in the toy.
3. **No bracket cue on the name column.** The name cell is its own segment (segs[0]) and the `[...]` lit-field cue only wraps `cells.slice(1)`, so with castCol 0 (name lit) the bracket is absent. The title bar names the field, so it stays legible; the cue just skips that one column.