REQUEST_CHANGES — one real bug in the sweep; the rest is good.

**Blocking: `scripts/tmux-sweep.sh` removes the socket on ANY failure of `tmux -S … display`, not only "no server running".**
- `tmux` not on PATH (exit 127): every socket owned by the uid goes.
- A live server of a different tmux version (after a nix/tmux upgrade; long-lived `tlon-office` or seat servers): the client fails with "protocol version mismatch", the live socket is removed and the server is orphaned.
- Any transient or permission error does the same.
The header promises "a live one answers and stays, a dead one fails 'no server running' and goes"; the code doesn't check that. The task exists to delete a pile of 464 sockets that include the operator's live ones, so it has to be conservative.

Fix: decide on the error text, and refuse when tmux is missing.
```
command -v tmux >/dev/null || { echo "tmux-sweep: no tmux on PATH, nothing swept" >&2; exit 2; }
...
  err="$(tmux -S "$sock" display -p ok 2>&1 >/dev/null)" && continue
  case "$err" in
    *"no server running"*|*"error connecting"*) rm -f "$sock" && removed=$((removed + 1)) ;;
  esac
```
Add a self-test case: a stub `tmux` earlier on PATH that prints "protocol version mismatch" and exits 1 must leave the socket in place.

Fine as is: the `killServer` fallback path (`${TMUX_TMPDIR||/tmp}/tmux-<uid>/<name>`) is correct, its test uses a private TMUX_TMPDIR with the env restored in `finally`; manual/tasks.md is regenerated; not running the sweep here is right.
Not verified: I read the diff only and ran no suites.