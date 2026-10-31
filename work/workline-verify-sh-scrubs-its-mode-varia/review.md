APPROVE

Right then: the spots read plainly.

- `scripts/workline-verify.sh:41` adds `-u WORKLINE_GATE -u LAND_REF -u RUN_TASK -u RULES_ONLY` to `clean`. I grepped every use of those four in the script (lines 27, 42, 46, 48, 59, 103, 121, 131, 192, 206, 230). All are script-level reads of its own env, and none depends on the value reaching a child. So the scrub cannot change the script's behaviour; it only stops the suite from inheriting them.
- `CHECKS_LABEL` is correctly left alone. It is re-set explicitly on the next lines and read by `checks-queue.sh`.
- The tests are better for this change. The `nil` entries in the `gate/2` and `verify/2` helpers were masking the bug, because the test cleared the variables before the script saw them. They are gone. The new test "the suite inherits none of branch mode's variables" sets `RUN_TASK`, which `gate/2` already sets alongside `WORKLINE_GATE` and `LAND_REF`, and asserts the stub gate's `env | grep` output is empty. That exercises the real path.
- The PR description reports RED, then GREEN (30 tests), then the full gate (2475 tests, 0 failed). I did not rerun them. The diff and the grep above are what I checked.

Nit, not blocking: the `pr.md` trailer names `claude-haiku-5-5`. That is the builder's call, so I left it.