No free reviewer was at the builder's grade (greybeard), so runeberg (Ollama, glm-5.2) leads this review.

**Verdict: approve.**

Since the last review at a0c43ba, one commit landed: 8df2b35, a 13-line regression test in
`office/test/cast-view.test.ts`. It pins the real reopen path — `C-]` (tmux's name for ctrl+])
home, then backtick back into the cast — and asserts both seats (ada, bo) are still listed and
"nobody on the bench" is absent. QA's reopen "bug" was the drive typing `ctrl+]` as six literal
chars, whose stray `]` stepped to the next (empty) workspace; this test goes red under that and
green under the real key (fact #2862). Correct, targeted, and the gates carry it (office:check
801/0, `mise run check` exit 0, both recorded at 8df2b35).

The editor logic is unchanged from the round I already approved: `cast.ts` is pure and
unit-tested, the `seatActions` split into `pickModel`/`pickPersona`/`unseatAsk` is
behaviour-preserving, sandbox isolation is proven (`cast-sandbox.test.ts`), and every key passes
`keys.test`. Nothing in 8df2b35 touches any of that.

The prior round's pr.md follow-up is dropped: `Server.Workline.Publish.body/3` (publish.ex:236)
falls back to the spec/plan heading when `pr.md` is absent, so it was never required for the
merge gate.

## Follow-ups (non-blocking, still open)

1. **y is a silent no-op on fields with no reroll.** `reroll` (main.ts:1886) wires only look,
   grade and specialty; on voice, soul, model, name and archetype the `y` key fires and does
   nothing. office/AGENTS.md now scopes `y` to "rerolls look, grade or specialty", so the
   behaviour is documented — but the key still binds on every lit cell. Could hide or relabel
   `y` when the lit field has no reroll.
2. **Sandbox unseat still asks.** `unseatAsk` always runs `ask2`, so `-` in the toy prompts y/n.
   Spec §3 says sandbox skips the confirm and the toy answers locally. Minor — one y/n in the toy.
3. **No bracket cue on the name column.** The name cell is its own segment (segs[0]) and the
   `[...]` lit-field cue only wraps `cells.slice(1)`, so with castCol 0 (name lit) the bracket is
   absent. The title bar names the field, so it stays legible; the cue just skips that one column.