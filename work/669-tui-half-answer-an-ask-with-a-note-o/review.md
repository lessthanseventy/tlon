# Review — 669 TUI half: answer an ask with a note

**Verdict: request_changes.** Read at 69be652 (branch diff from merge-base bf9bf75: 4 files, +80). The inbox path does what the ticket asks, and the server premise holds. Two things are wrong about what the change *says* it does, and the one surface the ticket is about has no test.

## The premise, verified

`Server.Attention.pick_key/2` (attention.ex:476) splits the body on the first whitespace, matches the first word to an option key case-insensitively, and hands the rest along; `answer/5`'s ask clause (:495) posts `"<to> <question> → <label> — <rest>"` on the asker's thread. attention_test.exs:365 already proves `"go after the cut"` → `"… → go — after the cut"`. So `{"key": "no the old one leaks"}` from the inbox shows the option and the note on the asker's thread. The operator's done-criterion is met on that path without a live run.

## Findings

**1. The thread-card binding never reaches an ask; it reaches pane dialogs and the release gate.**
`threadActions` reads `threadOf(tid)?.prompt`, which is `Server.Office.status`'s `prompts[t.id]` (office.ex:380), which is `Attention.open_prompts_by_thread/0` (attention.ex:221):

    where: m.kind == "prompt" and is_nil(m.resolved_at) and fragment("NOT (? \\? 'ask')", m.payload)

Asks are filtered out. A thread card's prompt is a coworker pane's dialog (or the PM's release gate on the root thread). So `thread.n` (`"` on a thread card) sends `"<key> <note>"` to `answer/5`'s pane clause (:525): it types the key into the pane, sleeps, types the note as its own burst, then Enter. That is the server's supported shape (the `"3 use mise, not a bare mix"` test at :266 is this path), so nothing breaks, but:

- The brief said "leave the modifier off dialogs, or document what it does there." It is on, and undocumented.
- pr.md says "dialogs (which type into a pane) get no note key." That sentence is false for the thread card, and the operator reads pr.md at the gate this stage exits through.
- Banked fact 4265 ("the note key on an ask card") is half right: on an ask it is the inbox card only.

Fix, your pick: (a) keep `thread.n` and say what it does — in pr.md, and in the keys.ts label or mode (e.g. mode `"an open prompt — on a pane dialog the note is typed after the key"`), or (b) drop the two thread-card lines (keys.ts `thread.n`, main.ts :971) and leave pr.md as written. I'd take (a): a "No, and tell it what to do differently" dialog answered with the reason is exactly what the server built that clause for, and the card otherwise has no note path.

**2. The test drives the dialog-shaped thread prompt, not the inbox ask.**
answer-note.test.ts' stub puts `prompt: {id: 77, …}` on a thread (a shape the real server emits only for dialogs/the gate) and returns `[]` from `/office/needs`. So the one surface where an ask actually appears — `needActions`' `need.n.ask` row, with its `n.ref`/`n.options!`/`after` wiring — runs nowhere. Add the inbox case: a `/office/needs` row `{kind: "ask", ref: 77, options: [...], ask: "ada", thread_id: 10, level: "decide", …}` (entry-keys.test.ts has a need fixture to copy), `i` → the card → `"` → `"2 the old one leaks"` → Enter → the same body, then a one-tap `no` (the inbox's one-tap keys are the option keys, not digits) sends the bare key. That is the test the brief asked for first.

## Not blocking (follow_ups)

- The note box asks for the option's *number* while the inbox card's one-tap keys are the option's *key* (`go`/`hold`), so the hint and the box disagree on what to type. Accepting the key or label as the first word too would cost one `find` (the server already matches either).
- `s.trim().split(/\s+/)` then `join(" ")` collapses runs of whitespace inside the note. Harmless in a one-line box; say so or keep the raw rest.

## Checks

- `mise run check` green on the server's verify (office: 914 pass, 0 fail). No bench_contrast row.
- Not run by me: the TUI live. Not needed for the verdict: the facts above are in the server source and its tests.
