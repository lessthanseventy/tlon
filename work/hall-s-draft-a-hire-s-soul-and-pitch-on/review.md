# Review — hall `W`: draft a hire's soul and pitch (#660) @ 113a5c5

**Verdict: approve.** Round two. The diff since my request_changes at 0bec330 is the four lines I posted, and nothing else; the gate re-ran green on this head. The code findings from round one stand as verified.

## Fixed since 0b9ed86

`git diff 0b9ed86..113a5c5 -- . ':!work/…'` is 3 files, 4+/3-:

1. **B1 closed.** `office/kit/hall.ts:247`, `office/tui/data.ts:196` and `operator_api.ex:1056` now say `W`. A grep of HEAD for the old "the hall's `s`" / "`s` in the hall" / "`s`: the server" phrasings returns nothing.
2. **B2 closed.** `operator_api.ex:112` lists `POST /api/workspaces/:id/hire/draft` in the moduledoc's route list, right after the `coworkers` POST, shape and "nothing written, nobody seated" included.
3. **No code path touched.** Every changed line is a comment or a moduledoc line, so round one's verification holds unchanged.

## Verified (carried from round one, re-read at this head)

1. `Soul.preview/2` keeps `body/2`'s order (sample → model → template), tags the source, writes nothing; `body/2` delegates so `draft/2` and every hire write the same text as before. `soul_test.exs` refutes `newhire.md` after a `:model` preview.
2. `draft_hire/2` validates `name` through the same `name_ok/1` as `hire/2`; `archetype` is free text that reaches only the model prompt (`Persona.voice/2` falls through on an unknown one). 200 fallback, 200 model (stubbed CLI), 400, 404, 422 all covered in `gateway_test.exs`; bench unchanged and no soul file after both drafts.
3. Office: `drawn` is in `EDITABLE`, so `applyOverrides` lays the draft on and `pass` drops it unless locked; both covered in `hall.test.ts`, with a `saveHall`/`loadHall` round trip. `hallDraw` drops a late result if the candidate changed. The render never calls the server.
4. **Gate:** `mise run check` exit 0 on this branch (CHECKS 19:03: office 964 pass, 0 fail; server green). The row's "tlon/check: not posted" is the verify checkout's tree state, not a failure. `bench_contrast` is unmeasurable (office/AGENTS.md is not loaded by the bench), not a regression: no finding, no habit.
5. **Spec deviation, sanctioned:** the key ships as `W`, not the ticket's `s`. `s` is `sort` in four scopes and `keys.test.ts` forbids two verbs on one key; plan task 3 said to pick a free letter and say so, and the builder did (pr.md, #21819). The operator should know this at the gate.

## Non-blocking

Follow-ups 1–3 carried from round one, listed after this verdict. The builder dropped 1 and 2 as outside this change's lines (#21850); 3 remains owed to the gate or QA.
