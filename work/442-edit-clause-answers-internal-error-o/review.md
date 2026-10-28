APPROVE — #442 edit_clause refused write

Read the diff (tools.ex, tools_test.exs, pr.md). Not run: both run_verb test attempts died with "Could not find a Mix.Project" in this seat, so the new tests are UNVERIFIED by me; verify runs the real gate.

`File.write!` becomes `File.write` returning `{:error, "<abs>: <posix reason>"}`, and a function-level `rescue` turns any other raise in the clause path into `{:error, Exception.message(e)}`. Fits the ask; surgical; the comment is a load-bearing why.

Non-blocking notes:
- Error names the absolute path, not `rel`; the test asserts only "demo.ex", which the abs path contains.
- The chmod 0o444 test fails if the suite runs as root.
- The rescue drops the stacktrace; an empty exception message replies "".
- Test 1 (multi-line body-only replace) is a pin, not a regression for the fix.