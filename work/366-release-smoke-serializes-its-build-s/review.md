# Review — 366-release-smoke-serializes-its-build-s @ bd4c6ad

**Verdict: request_changes** — the change is correct against the spec (my earlier approve stands on substance: 8/8 script test here, full gate green on this head at 06:36:49Z). Two findings sit in lines this diff already touches, and the follow-up rule says those land with the change, not after it. Both are small; the exact edits are below.

## 1. Close fd 5 inside the build subshell (scripts/release-smoke.sh, the `) >>"$log" 2>&1 || {` line this diff rewrote)

The build subshell and every child it spawns — mix, the migrate node, an epmd it may start on a box with no service up — inherit the lock fd. A daemonized child that keeps it holds the machine-wide lock after the smoke exits, and every later build on the box waits on `waiting for pid N (sha)'s build`. Only the parent shell needs to hold it:

```
-  ) >>"$log" 2>&1 || {
+  ) 5>&- >>"$log" 2>&1 || {
```

And a case in scripts/release-smoke.test.sh that goes red without it (after the killed-holder case):

```
: >"$log"
( . "$here/lib/smoke-build.sh"; smoke_build_lock "$lock" L >/dev/null; ( sleep 5 & ) 5>&-; echo "end L" >>"$log"; smoke_build_unlock )
build D 0 & until_log "end D"; wait
expect "a build that leaves a child behind does not block the next build" "$(grep -c '^end D' "$log")" "1"
```

(With `5>&-` dropped from the fake build's `( sleep 5 & )`, the orphan holds the lock and D never ends — the red case.)

## 2. tasks/server.toml: name the new test in check:names' description

The description enumerates each self-test the task runs. Add a clause, e.g. `…, checks-queue.sh runs waiters first come first served, release-smoke.sh builds one at a time and names a pool failure (…)`.

## Already verified, unchanged

- Spec (a) and (b) met; unlock precedes the server start and the hold branch; fd 5 collides with none of 6/7/8/9; `fail` exits so a dead build frees the lock; the fake-checkout copy lists carry lib/smoke-build.sh.
- Cosmetic, no action: a waiter that reads the lockfile between the holder's `flock` and its `printf` sees the previous holder or "someone".