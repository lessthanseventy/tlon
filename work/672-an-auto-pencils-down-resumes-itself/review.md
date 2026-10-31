Verdict: approve. Reviewed below the builder's grade: no free reviewer is at senior grade, so this is a haiku-grade read.

Read the diff (server/lib/server/pause.ex, server/lib/server/jobs/auto_resume.ex, tests). Ordering in auto/1 is right: go/1 clears pause_by before "auto" is set. auto_resume/2 matches the latch by window string. Lights out is untouched.

Not verified: I did not run the test suite; the pr.md test claims are the builder's.

Follow-ups are in follow_ups.