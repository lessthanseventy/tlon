APPROVE — #438 requeue cap tells the sheriff once per approval, marked only once the sheriff is told.

Read the full diff (workline.ex, workline_test.exs) and ran `menard run test` on workline_test.exs: 78 tests, 0 failed.

Checked:
- `approval/1` now carries the approval event's id; other callers match only "by"/"sha"/"at", so nothing breaks.
- `requeue_or_drop` returns `:dropped` at the cap, which the `{:ok, queued} <-` generator filters out, so `requeue_stranded` still returns only the queued threads.
- The earlier follow-up is fixed in c9b46ec: the `dropped` marker post (keyed on the approval id) is written only when `Sheriff.report` returns `:ok`. With no sheriff seated the cap stays unmarked and the next tick reports once one is. A test covers this.
- A fresh approval gets a new id and its own discard window, so it is reported afresh; a test covers the reset.
- The doc matches the behaviour.

Non-blocking: the told-check and the post are not atomic, so concurrent ticks could report twice. That is harmless at this rate.