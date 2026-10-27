APPROVE — #438 requeue cap tells the sheriff once per approval.

I read the diff (workline.ex, workline_test.exs) and Sheriff.report. I did not run the suite myself; the gate does that at verify and at landing.

Checked:
- `approval/1` now carries the event id. The other callers only match on "by"/"sha"/"at", so the extra key breaks nothing.
- `requeue_or_drop` returns `:dropped`, which the `{:ok, queued} <-` generator filters out, so `requeue_stranded` still returns only the queued threads.
- Dedup is keyed on the approval's event id, stored as a string in the thread post's `dropped` payload. A later tick finds it and stays quiet; a fresh approval has a new id and is reported afresh. The reset test covers both.
- The doc matches the new behaviour.

Non-blocking, in follow_ups:
- The marker post lands before `Sheriff.report`. `report` rescues and returns `:ok` or `:no_sheriff`, so a lost report still suppresses every later tick.
- The told-check and the post are not atomic. A double report from concurrent ticks is harmless at this rate.