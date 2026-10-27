# #438: a landing that hits the requeue cap tells the sheriff

Closes #438.

A landing discarded three times under one approval stopped being requeued, but the only signal was a boot-time `Logger.warning` when the discards came from Orphans. The sheriff was told only on a crash's last attempt, so a service restarted three times mid-landing parked at review with nothing on the board or the sheriff's beat.

Now `Server.Workline.requeue_stranded/0` tells the sheriff once when it finds the cap reached for an approval: the thread and the approval's sha, that the landing was dropped 3 times and is no longer requeued. The thread gets a `dropped` post carrying the approval's event id; a later tick finds it and stays quiet, while a fresh approval has a new id and is reported afresh. `approval/1` now returns that id. The cap's doc states what is true.

Checked: `server/test/server/workline_test.exs` gained three tests (cap reports once, a later tick does not repeat it, a fresh approval reports again). They failed before the change (no sheriff report) and pass after. workline_test 77/77; with sheriff, keep-up and landing suites, 372 pass.
