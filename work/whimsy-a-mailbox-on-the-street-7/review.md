APPROVE — scoped to what the operator chose ("ship it and make a follow up ticket").

Reviewed `office/kit/mailbox.ts` and `office/test/mailbox.test.ts` (commit fd69787) by reading them. I did not run the suite myself; the server's verify check passed on the branch.

- **Behaviour:** `mailbox()` maps needs to letters, capped at 5 drawn, with `total` counting all. Blocking needs raise the flag.
- **Accessibility:** the flag is a different shape from the lowered flag, so state is not conveyed by colour alone (office/AGENTS.md WCAG law).
- **Colours:** every colour is a `ROLE`; no literals.
- **Tests:** they cover empty, letters, flag, the cap, and the drawn output differing for mail, flag and empty.
- **Kit boundary:** no toolkit imports under `kit/`.

Gaps, all expected and tracked in follow-up #41:
- The mailbox is not placed on a street tile. No home-tile renderer exists yet.
- The needs feed from `tui/data.ts` is not wired in.
- The "coworker walks a letter over" errand is not built.
- The failing tmux window-screen test is unconfirmed (the builder suspects their sandbox).

No blocking findings.