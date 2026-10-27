# Review — 669 TUI half: answer an ask with a note

**Verdict: approve.** Read at 3ffe1b0 (branch diff from merge-base bf9bf75: 4 code files, +138; delta since my 5926b38 round is 3ffe1b0 alone). Both findings from the first round are fixed, both follow-ups taken, nothing new blocks.

## Findings from round 1, checked

**1. thread.n documented.** keys.ts:79 now carries mode `"an open prompt — on a pane dialog the note is typed after the key"`, and pr.md's false sentence ("dialogs get no note key") is gone; it now says the thread card's prompt is a pane dialog or the release gate, never an ask. That matches `Attention.open_prompts_by_thread/0` (asks filtered out) and `answer/5`'s pane clause (attention.ex:525: key, settle, note as its own burst, Enter). Fixed.

**2. The inbox ask is tested.** New answer-note-inbox.test.ts stubs `/office/needs` with `{kind: "ask", ref: 77, options: [y/yes, n/no], ask: "ada"}`, drives `i` → the card → `"` → three notes → Enter, and asserts the bodies land on `/api/office/prompts/77`, then a one-tap `y` sends `{key: "y"}`. That is `needActions`' `need.n.ask` row, with `n.ref`/`n.options!`/`after`, running for real. Fixed.

## Follow-ups from round 1, checked

- First word may be number, key or label: `answerWithNote` (main.ts:814) does `opts[Number(w) - 1] ?? opts.find(key or label, case-folded)`. The test sends `2 …` → `n …`, `y …` → `y …`, `no …` → `n …`. Done.
- Raw spacing kept: `/^(\S+)\s*([\s\S]*)$/` on the trimmed line, the rest sent as-is. The test's `"y  two  spaces"` → `"y two  spaces"` (leading gap eaten by `\s*`, the inner double space kept). Done.

## Also read

- Empty rest sends the bare key (`m![2] ? … : o.key`), so `"` then `y` then Enter equals the one-tap. Esc never calls submit (inputKey:2284), so cancel is silent; Enter on an empty box lands on the "start with the option's number, key or label" status, which is the right message.
- `"` has one verb per scope: card:need `note` (ask mode only), card:thread `note`, card:review `note`. keys.test.ts is in the green office run.
- Nit, not blocking and not worth a ticket: pr.md says the thread card's key "types the key into the pane and then the note" — on the release gate (attention.ex:517) there is no pane; the whole body is recorded as the reply and only the key reaches `Release.PM.answered/2`, so the note is kept on the thread but acts on nothing. keys.ts' mode is worded correctly ("on a pane dialog").

## Checks

- Server verify at 01:07Z: `mise run check` green (office: 915 pass, 0 fail, 130 files). No bench_contrast row in CHECKS.
- Not run by me: the TUI live against the service. Not needed for the verdict: both tests drive the real TUI against a stub server, and the server half is proved by attention_test.exs:365 (`"go after the cut"` → `"… → go — after the cut"`).
