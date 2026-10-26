office: a column's empty space opens the column (#177)

Card clicks already open the thread (f71095e). This adds the other half: the blank area of a board column — below its last line in the wide room, under the stickies in the rail — is now a `{kind:"column", col}` hit, so a click opens the column instead of clearing the slate. The hit is pushed after the column's card hits because `hitAt` is first-match.

Closes #177.

Checked: new tests in office/test/board-hits.test.ts (blank cell → column, every line/sticky still → its thread) went red before the change and green after; the existing ten-cell-size reachability test and rail.test.ts stay green.
