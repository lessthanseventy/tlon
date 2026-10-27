smoke: one parameterised fixture door, and every QA case through it (#685)

QA filed one ticket per feature for state a fresh smoke db lacks. `start_smoke`'s `fixtures` now takes
a spec, `name:key=value,key=value` (no spaces, so it still travels as one word through
`TLON_SMOKE_FIXTURES` and `release-smoke.sh`), and `Server.Smoke.Fixtures` is a catalog of
name → {param defaults, seeder}. An unknown param is refused; the next feature adds a catalog entry,
not a ticket. Only `Smoke.start/5`'s name regex changed on the pipe.

New fixtures, each seeded through the live contexts (Needs, Shifts, Tickets, Workline, Schedules,
Life, Staff), never a raw insert that skips a validation:

- `lead_change` (#555), `settled_need` / `passed_up_need` (#595), `life_routine_overdue` (#610),
  `landed_workline:flag=on|off` (#652), `failed_job` / `health_need:what=disk|mem|tmux` (#662),
  `interrupted_schedule_run` (#666), `quota_refused_need:provider=` (#678).
- `tool_denied_need` and `ticket_tree` work as before.
- The QA brief lists the catalog, the spec syntax, and that `drive_smoke` starts a fresh session per call.

The ticket's `name key=value` strings map 1:1 to `name:key=value` (the colon keeps a spec one word).
`life_routine_overdue` computes its cron from the server's local clock a few minutes back, so the
bedroom scene's "today, unstamped" holds at any hour except just after local midnight.

Two choices to look at: Uqbar's verdicts route only with `uqbar_routing` on, so those two fixtures
write it into a config file private to the smoke node (`:operator_config_path`), not the operator's
(#640 is still open for Settings edits generally); and `health_need` holds its reading in the node's
env, which lasts until the smoke is torn down.

Closes #685; replaces #555 #595 #610 #652 #662 #666 #678.

Checked: `fixtures_test.exs` has a test per fixture asserting the row it promises (each red first);
`jobs/smoke_test.exs` pins the spec grammar (params accepted; spaces, `$()`, quotes, `;` refused);
`release_smoke_script_test.exs` pins a spec with params reaching the rpc whole beside another;
`profiles_test.exs` fails if the QA brief omits any catalog name. Not run: a real `release:smoke`
with these fixtures (it needs the nightly's build node).
