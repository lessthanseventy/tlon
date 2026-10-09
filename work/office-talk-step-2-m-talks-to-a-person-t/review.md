VERDICT: approve

Re-review of e13951c (the fix for nolan's QA fail), on top of the earlier-approved talk work (talk.ts, m/' wiring).

- The collision was `M` twice on a coworker card: "move to project…" (threadActions, main.ts:519) and "model…" (seatActions, :534). The first one won, so the model picker was unreachable.
- Fix: move-to-project is now `P`. I listed every key on the coworker card in main.ts: m (talk), enter/c (live), v r A > S t g d h P x D (thread), M y C - (seat), l, esc. No key appears twice, and `P` is free.
- Spec: `m` posts `@name …` to the lobby and `'` posts unaddressed to the lobby. QA already drove both and they worked, with rows `@tertius hi tertius from QA` and `hello office from nolan QA`.

Open, not blocking:
- There is no unit test for the card key map, because it lives in tui/main.ts, which can't be imported. The fix is checked by typecheck and by reading, not by a test. A key-uniqueness assertion would catch this class of bug. That would be its own change.
- I did not run anything myself. The server gate passed on this branch, per the brief. emma ran the office suite in the sandbox: 307 pass, and the 2 tmux failures are sandbox-only (terminal.test.ts is 3/3 green unsandboxed).
- QA has to re-drive once: Tab to a coworker's card, `M` should open `TERTIUS'S MODEL`, and `P` the project picker.