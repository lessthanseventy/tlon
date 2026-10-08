VERDICT: approve

Read the full diff main...HEAD (server calendar/feed/office, office sim + lounge/kitchen tiles, types, AGENTS.md, tests). I did not re-run the gate myself; the server's verify (`mise run check`) recorded green on this branch.

- Prior round's findings are addressed: celebrations are cached per day and cleared on every fetch/refresh, so `Office.status/0` doesn't re-parse ICS per poll. A yearly series is not shown before its start year. The `types.ts` doc comment is back on `weather`.
- `Feed.celebrations/2` is scoped correctly: all-day events only, a title match on birthday/anniversary, yearly RRULE by month and day, anything else on its own date. Tests cover both paths.
- Office side is a small, additive change. Everything is gated on `a.celebrations?.length`, so older servers and absent data behave as before. `moment` is exported for the test, and the weight of 5 for cooler/coffee is the intended crowd pull. `office/AGENTS.md` is updated in the same change.

Non-blocking, nothing owed:
- A Feb 29 birthday only shows in leap years.
- The first `celebrations` call each day parses every feed inside the GenServer. That's a one-off, but a very large feed could approach the default 5s call timeout.