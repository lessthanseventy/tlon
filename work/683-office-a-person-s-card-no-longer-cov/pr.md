# office: a person's card no longer covers their conversation (#683)

Closes #683. Clicking a coworker put the whole soul + persona block after their thread, and the pane opens on the newest row, so the conversation sat off-screen.

- New pure `office/tui/person-card.ts`: closed, the card is at most one dim line (persona backstory, else first soul line); open, the full soul + persona.
- `person` case in `main.ts` uses it; the Sheriff's nameplate/mug/ledger go behind the same toggle. `threadRows` and the scroller are untouched.
- New bind `person.space` ("the card", listed in ACTIONS) toggles it; it resets closed on opening a person.

Checked: `office/test/person-card.test.ts` (red first: module missing); `bun run typecheck`; full office suite at OFFICE_TEST_HOUR=3 and 15, 928 pass / 0 fail. drive-office (sandbox) shows the ACTIONS entry and the toggle. NOT checked: a screenshot of a live coworker's messages — the server was down (:4040/:4041 unreachable) in this session.
