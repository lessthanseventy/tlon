# Review: 342 wide room's dog slot reads pets.json — at 888c5e2

**Verdict: approve.** Both of nolan's QA findings are fixed, each with a test that the builder reports red first. The gate is green on the branch (`mise run check` at 04:11Z: office 923 pass / 0 fail). No bench_contrast row in CHECKS this round or the two before it.

## 1. Adopt prompt — fixed

The witness, `office/tui/main.ts:253`:

    ask2(adoptAsk(old, c.name), () => {

and `office/tui/store.ts:40`:

    export const adoptAsk = (occupant: string, adopted: string) => `${occupant} leaves by the door. adopt ${adopted}?`

The dog branch's "(the room still draws Argos)" is gone; the cat's text is byte-identical to what it was, so the cat slot is unchanged. Pinned by `store-view.test.ts:39`.

## 2. talkOut strips known speakers only — fixed

`office/rooms/wide.ts:641-642`:

    const cats = ["Nina", this.cat.name], speakers = [...cats, "Argos", this.dog.name]
    … const who = speakers.find((n) => turn.startsWith(`${n}:`)); … text: who ? turn.slice(who.length + 1).trimStart() : turn

The colon is part of the match, so a name that is a prefix of another ("Argo" vs "Argos:") cannot steal a turn. "Note: woof" reaches the dog whole (`pets.test.ts:415`); "Mimi: hush" on a renamed cat is hers, said without her name (`pets.test.ts:424`). That is the grader's proof gap closed on both counts.

Ran here: `bun test test/pets.test.ts test/store-view.test.ts test/wide.test.ts test/sim.test.ts` → 102 pass, 0 fail; `bunx tsc --noEmit -p .` clean.

## Still open, non-blocking

The menu literal "Argos, the dog" (`main.ts:923`) and the home line "or Nina, or Argos" (`:1236`) still name the defaults after an adoption. Not in lines this change touches, and the cat has the same literal; listed as a follow-up so it is not lost.

## Checked and fine (unchanged since 772a54a)

Coat ramp, pet card title, store card occupant, `this.line("Argos", …)` role key (fact 4320), `p.dog.shade ?? 0` clamp, pr.md's spec note.