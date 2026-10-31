APPROVE. Right then.

Read a3d31b7 (3 files). Not run: tests/gate (no sandbox access here); verified by reading only.

- Fix is correct: dropping `stderr_to_stdout` on `gh pr view` and `gh api` keeps warnings off the JSON/"false" parse. The new test models System.cmd's stderr merge faithfully and would fail on the old code.
- `queue/5` defaults keep `queue/3,4` callers intact (tests, `scripts/tlon-cli.sh:599`). `:by` flows land_pr → request → queue → post; nil stays silent. Fine.

Non-blocking: `unprotected/3` still prints "gh said: #{said}" from stdout, but on a non-zero exit gh's explanation is on stderr, now uncaptured, so that message will read "gh said: " (blank). Diagnostic regression, not a correctness one; see follow-up.