APPROVE

Right then. The diff is small and the hint now says what is true in each place.

- `lookHint(hall)` in `office/tui/hall.ts` returns the hall line when `hall` is true and keeps the old room line otherwise. `main.ts` calls it with `!!m.hall`. The `lookDraft` initialiser two lines above branches on the same `m.hall`, so the hint follows the same source of truth as the draft.
- The new test in `hall-view.test.ts` pins both strings exactly.
- The change is surgical: no unrelated reformatting, and no AGENTS.md or spec text is affected.
- I read the diff only. I did not re-run `office:check`. The PR description reports it green (965 tests at both `OFFICE_TEST_HOUR` values), and I did not verify that.
- Behaviour I did not verify: that `_` in hall mode really writes to `looks.json` at hire, as the new hint claims. The diff does not touch that path, and the claim comes from the PR description.