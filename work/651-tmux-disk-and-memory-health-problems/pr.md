Closes #651. The box's own failures become keyed needs routed like the rest (Uqbar first).

- New need kind `health`: `health:tmux`, `health:disk`, `health:mem` (90%), derived in `Needs.all/0`
  from `Room.vitals/0` (tmux, disk, mem only; cached 60s because `df` forks and the list is polled).
  Each item is gone when its predicate is false. Clipboard surface, job_failed's narrow pass-up rule;
  named in the moduledoc table and the TUI `kind` union. db-down and jobs-failed left out on purpose.
- `tlon-cli job retry|dismiss <id>`: the two calls behind POST/DELETE `/api/office/jobs/:id`
  (`Needs.retry_job/dismiss_job`), via the CLI's usual rpc. Uqbar's role names them.
- Test for `job_failed` in Uqbar's group (the code was already on main).
- test config stubs `:health_reading` healthy so the suite doesn't read the dev box's disk.

Checked: needs, room, profiles and tlon_cli tests green; full `check` via run_task.
