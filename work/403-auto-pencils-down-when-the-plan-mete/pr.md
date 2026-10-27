# Auto pencils down when a plan meter nears its cap

Closes #403. When a reported plan window (5-hour or weekly) reaches the new `auto_pause_at` knob
(default 90), `Server.Usage.report/1` calls `Server.Pause.auto/1`: the office goes to pencils down and
the root thread says why. It fires only from `:working`, and never twice for the same
`{window, resets_at}` (latched in the settings file), so the operator's `back_to_work` sticks. A manual
pencils down or lights out is left alone.

Deviation from the spec: the knob is an int 1–100, not nullable (`OperatorConfig.value/2` turns nil
into the default, so nil could never mean off); 100 is as near off as a meter gets. No auto-resume
here: follow-up #672.

Checked: `menard run test` on operator_config, pause, usage tests; `menard run check --in server`
green (2237 tests, 0 failed).
