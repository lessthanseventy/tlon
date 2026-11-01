APPROVE. Right then: the read is clean.

`open_counts/2` now skips a started (`doing`) loose ticket in `loose` but still counts it in `total`. That is the whole server change (`room.ex`). `loose_open` feeds both `Room.board` and `ticket_open` (`office.ex:55`), so the header and the whiteboard sticky now share one meaning of loose. The `types.ts` doc line matches. The test change flips the assertion that encoded the disagreement (2 to 1), which is correct.

Not independently run: I did not re-run the gates. The RED/GREEN, check and office:test counts are the builder's report. I checked that the row-side drop of started loose tickets lives client-side (the server `loose` list still includes them), as the PR says.

No follow-ups.