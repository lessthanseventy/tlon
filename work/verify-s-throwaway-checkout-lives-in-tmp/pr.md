# workline-verify: the throwaway checkout lives under the verify cache, not /tmp

Closes #522.

`scripts/workline-verify.sh` made its throwaway checkout with `mktemp -d -t tlon-verify-XXXXXX`,
which lands in `/tmp`. Every seat's sandbox writes `/tmp`, and every git repo under a write root
costs bwrap arguments. The verify's suite seeds hundreds of repos, so any seat that ran a verify
overflowed its 9000-argument cap (`Sandbox profile has 11047 bwrap arguments`).

The checkout and its stale sweep now share one root, `${XDG_CACHE_HOME:-$HOME/.cache}/tlon-verify`,
outside every seat's write roots.

Checked:
- RED: the new branch-mode test asserts the gate's checkout is under `$XDG_CACHE_HOME/tlon-verify/`.
  It failed on the old `mktemp` (checkout under `TMPDIR`).
- GREEN: `menard run test --in server test/server/workline_verify_script_test.exs` → 19 tests, 0 failed.
- `bash -n scripts/workline-verify.sh` → clean.
