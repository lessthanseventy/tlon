# Wake-overdue alert: don't page a seat whose pane is gone

Closes #543.

`Server.Wake.report_overdue/1` paged the sheriff for any overdue wake. A wake to a seat with no live
session, no window on the thread, or that no longer holds the workline's current stage can never be
drained, so the page was noise (seen for treviranus after a send_back, and runeberg twice).
Such a wake is now let go unpaged; `Switchboard.redeliver_unheard/1` and staffing already handle a
lead that moved on. Liveness reuses the office's window read (`Server.Office.windowed?/3`, now public)
plus a live `Server.Session`; a tmux that can't be asked is not read as "no window".

Checked: `menard run test --in server test/server/wake_test.exs` red on the new tests before the
filter (4 failing), green after; `menard run check --in server`: 1974 tests, 0 failures.
