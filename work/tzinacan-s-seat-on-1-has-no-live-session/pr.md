# A superseded session claims its seat again once the newer one is gone

Closes ticket #391 (issue #36).

A session told "superseded by a newer session" latched `superseded` in the tlon-citizen mod and
stopped polling for good. When the newer session then ended (its pane died, or it was reconciled),
the seat had no live session and nobody drained its wakes.

Now the superseded session still asks `take_wakes` each poll: it takes nothing and says nothing
more while a newer session holds the seat, and when the server answers with wakes (no live
session) it registers again and resumes.

Checked: `claude plugin test` on the mod's stage — 34 pass, incl. the new test
"a superseded session whose newer one is gone claims the seat again instead of staying stopped"
(red before the change: 1 register, expected 2).
