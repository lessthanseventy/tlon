Whimsy: a streak photo hangs on the living tile's wall (#27).

A routine whose streak reaches 7 hangs a photo on the living tile. The tier (7, 30, 100) is the highest milestone reached and shows as a bar under the photo, so it reads without colour. A streak below 7 hangs nothing, so a lost streak takes the photo down. Frames are derived from the streaks view and never stored. The milestone list is one helper, for the trophy shelf to reuse later.

Build mode now fetches the home's life status so the wall is current. Office only; no server change.

Closes #27.

Checked: RED first (life.test.ts would not load on the missing `streakFrames`; two homeart frame tests failed). Then GREEN: the targeted tests pass (40 pass, 0 fail), the full office suite passes (842 pass, 0 fail, 121 files), and `tsc --noEmit` is clean.

Open: this branch carries 64 commits from other worklines that are not #27's (#578 and workline 516). Rebase onto main before landing is pending tertius's call.
