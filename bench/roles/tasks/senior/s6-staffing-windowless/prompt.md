Ticket: sessions pile up. A `Server.Session` (an agent's instance on a thread) is ended only when a
successor replaces it, so one whose tmux window is gone — swept cold, or killed by a stop/restart —
stays open for good, and the room and roster keep counting it (19 open live, 7 idle 2h+ with no
window). Make the staffing pass end such sessions.

`Server.Staffing.pass(workspace_id)` (`lib/server/staffing.ex`) already reads the tmux tabs and runs
`resume_interrupted/3` for mid-turn sessions. Add a step to it that ends, with `Server.Staff.end_session/1`,
every session in that workspace that:

- is open (`ended_at` nil), belongs to a coworker on the workspace's bench (the `bench` list the pass
  already has), and is **idle** (`thinking_since` nil) and has been inactive longer than the boot grace
  (`@boot_grace_s`; `last_active_at` older than that — a younger one may still be booting); and
- has **no window**: no tab for its thread (`tab.thread_id == thread_id` or `tab.name == "t<thread_id>"`)
  whose agent is that coworker (or unset), and — for the workspace's standing thread — no tab of its own
  (`thread_id` nil and the tab's agent or name is the coworker).

Mid-turn sessions stay `resume_interrupted`'s; a session whose window still runs stays open. Add a test
to `test/server/staffing_test.exs` (it has `staffed_thread/2`, `session!/3` and a `tmux/1` stub for the
tab listing); keep `mix test` green.
