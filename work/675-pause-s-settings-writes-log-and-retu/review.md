APPROVE — re-review of head 4afc780.

Right then: the chipped mug holds. Checked the diff since d1061b3:
- `Pause.change/3` writes `pause`, `pause_by` and (auto) the latch in one `OperatorConfig.put_many` write, so a failed write leaves the file as it was. No half-state, and `auto/1` does not latch a window it failed to pause.
- `put/3` delegates to `put_many/2`, so existing callers are unchanged.
- The office pause route turns `{:error, _}` into a 500 instead of a MatchError.
- Tests: `menard run test` on pause, operator_config, usage and gateway tests: 105 run, 0 failed. I did not run the full gate; verify does.

No blocking findings.