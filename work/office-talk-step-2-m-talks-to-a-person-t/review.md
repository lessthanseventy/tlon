VERDICT: approve

Re-review after emma's rebase onto origin/main (the AGENTS.md conflict).

- Diff vs plan: talk.ts (lobbyOf/speech/say), `m` on a coworker card posts `@name …` to the lobby, `'` posts unaddressed. Both match the spec. talk.test.ts covers lobby choice, addressing, the post path and the no-lobby case.
- Keys: the coworker card has v r A > S t g d h P x D (thread), M y C - (seat), m (talk), l, esc. No duplicates after the rebase. `M` is the model picker and `P` is move-to-project. `'` is a new global and is not claimed elsewhere.
- office/AGENTS.md keeps main's sandbox lines and adds the `talk.ts` pointer, so the doc is in sync.
- I read the diff and grepped the key map. I did not run the suite. Per the thread, emma ran office:check at 318 pass / 0 fail after the rebase, and the server's verify stage passed.

Open, not blocking: nothing tests that the card keys are unique, because that map lives in tui/main.ts, which can't be imported. That would be its own change.