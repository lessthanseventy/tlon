# #166 A — FIFO checks queue: plan

Spec: `work/166-a-fifo-checks-queue-scripts-checks-q/spec.md`. Five tasks, each its own commit, in order. Every gate on the machine runs through `scripts/checks-queue.sh`: do not skip a verify step.

**One deviation from the spec:** the script tests are a bash self-test, `scripts/checks-queue.test.sh`, not an ExUnit file. The repo already does this (`scripts/scratch.test.sh`, wired into `check:names`), it needs no Postgres and no Elixir build, and a seat can run it. Same cases as the spec. The `Room.checks/0` test stays ExUnit.

**One improvement over the spec:** the wait entry is written *inside* the ticket's `flock`, so there is no window where ticket 3 is taken but not yet visible while ticket 4 sees itself as head and takes the lock.

Run commands from the worktree root. `menard` = `~/projects/menard/bin/menard`. The shell test needs `flock`, `setsid` and `/proc` (Linux); run it unsandboxed if your Bash can't open `$TMPDIR` locks (it uses a private tmp dir, so a sandbox is usually fine).

---

## Task 1 — `Room.checks/0` reads `<seq>-<pid>` entries in ticket order

Files: `server/test/server/office/room_test.exs`, `server/lib/server/office/room.ex`.

**1a. Failing test first.** In `room_test.exs`, in the test `"the checks queue: who holds the lock and who waits, ..."`, replace these lines

```elixir
    me = System.pid()
    File.write!(Path.join([dir, "tlon-checks.wait", me]), "mise run check:all (pid #{me}) in /v since 21:50:00\n")
    File.write!(Path.join([dir, "tlon-checks.wait", "999999999"]), "gone\n")

    assert %{running: "mise run check:all (pid 1) in /w since 21:49:17", waiting: [waiter]} = Room.checks(dir)
    assert waiter =~ "in /v"
```

with

```elixir
    me = System.pid()
    wait = Path.join(dir, "tlon-checks.wait")
    File.write!(Path.join(wait, "0000000002-#{me}"), "second (pid #{me}) in /v since 21:50:01\n")
    File.write!(Path.join(wait, "0000000001-#{me}"), "first (pid #{me}) in /v since 21:50:00\n")
    File.write!(Path.join(wait, "0000000003-999999999"), "gone\n")
    File.write!(Path.join(wait, "junk"), "not an entry\n")

    assert %{running: "mise run check:all (pid 1) in /w since 21:49:17", waiting: ["first (pid" <> _, "second (pid" <> _]} =
             Room.checks(dir)
```

Also rename the test's title tail to `..., a waiter whose process is gone not counted, waiters in ticket order`.

Red: `menard run test --in server test/server/office/room_test.exs` → fails (old code looks for `/proc/0000000001-…`, finds none, `waiting: []`).

**1b. Make it green.** In `room.ex`, `checks/0`, replace

```elixir
      for name <- ls(Path.join(dir, "tlon-checks.wait")),
          File.exists?("/proc/#{name}"),
```

with

```elixir
      for name <- Enum.sort(ls(Path.join(dir, "tlon-checks.wait"))),
          [_, pid] <- [Regex.run(~r/^\d{10}-(\d+)$/, name)],
          File.exists?("/proc/#{pid}"),
```

(use `menard edit`; the second `for` generator filters non-matching names). In the `@doc` above it, change "the ones waiting their turn" to "the ones waiting their turn, in ticket order (entries are `<10-digit ticket>-<pid>`)".

**Done:** `menard run test --in server test/server/office/room_test.exs` green. Commit: `room: checks/0 reads <ticket>-<pid> wait entries in ticket order`.

---

## Task 2 — the failing shell self-test

File (new, `chmod +x`): `scripts/checks-queue.test.sh`.

```bash
#!/usr/bin/env bash
# Self-test of checks-queue.sh: waiters run in the order they arrived (even one arriving as the slot
# frees), a killed waiter does not block the line, two checks never overlap, and bookkeeping that
# cannot be written falls back to a plain lock. Runs the real script against a private runtime dir.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT
bad=0
export XDG_RUNTIME_DIR="$tmp/run" CHECKS_POLL=0.05 TLON_STALE_SCRIPTS_OK=1
unset CHECKS_UNQUEUED
log="$tmp/log"; err="$tmp/err"
fresh() { rm -rf "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_RUNTIME_DIR"; : >"$log"; : >"$err"; }
# job <name> <seconds>: a check that logs its start and end
job() { CHECKS_LABEL="$1" "$here/checks-queue.sh" bash -c "echo start $1 >>'$log'; sleep $2; echo end $1 >>'$log'" 2>>"$err"; }
queued() { ls "$XDG_RUNTIME_DIR/tlon-checks.wait" 2>/dev/null | wc -l; }
until_queued() { local i=0; while [ "$(queued)" -lt "$1" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
until_log() { local i=0; while ! grep -q "^$1" "$log" && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
starts() { grep '^start' "$log" | cut -d' ' -f2 | tr '\n' ' '; }
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; bad=1; fi; }

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
job C 0 & until_queued 2
wait
expect "A, B, C run in arrival order" "$(starts)" "A B C "

got=""
for _ in $(seq "${CHECKS_RACE_LOOPS:-20}"); do
  fresh
  job A 0.3 & a=$!; until_log "start A"
  job B 0 & until_queued 1
  wait "$a"; job C 0 &
  wait
  got="$(starts)"; [ "$got" = "A B C " ] || break
done
expect "C arriving as the slot frees runs after B (${CHECKS_RACE_LOOPS:-20} rounds)" "$got" "A B C "

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
bpid="$(ls "$XDG_RUNTIME_DIR/tlon-checks.wait" | head -1 | cut -d- -f2)"
job C 0 & until_queued 2
kill -9 "$bpid"
wait
expect "a SIGKILLed waiter does not block the line" "$(starts)" "A C "
expect "its entry is reaped" "$(queued)" "0"

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
bpid="$(ls "$XDG_RUNTIME_DIR/tlon-checks.wait" | head -1 | cut -d- -f2)"
kill -TERM "$bpid"; sleep 0.3
expect "a TERMed waiter removes its own entry at once" "$(queued)" "0"
wait

fresh
for n in 1 2 3 4; do job "J$n" 0.1 & done
wait
expect "two checks never overlap" "$(awk '{ if ($1 == prev) bad = 1; prev = $1 } END { print bad ? "overlap" : "serial" }' "$log")" "serial"
expect "all four ran" "$(wc -l <"$log" | tr -d ' ')" "8"

fresh
: >"$XDG_RUNTIME_DIR/tlon-checks.wait" # a file where the dir should be: bookkeeping cannot be written
job A 0 &
wait
expect "unwritable bookkeeping still runs the check" "$(starts)" "A "
expect "…and says it fell back" "$(grep -c 'falling back' "$err")" "1"

exit "$bad"
```

Red: `scripts/checks-queue.test.sh` → against the current script at least the "SIGKILLed waiter" and "TERMed waiter" cases fail (old waiters are named `<pid>`, so `cut -d- -f2` is empty and the kill targets nothing: those two print FAIL), and the fallback line fails; the order cases may flake red. Say in the commit message which failed.

**Done:** the file exists, is executable and exits 1 on the old script. Commit: `scripts: checks-queue self-test (red: ticketed FIFO not built yet)`. (A red commit is fine on a branch; Task 3 turns it green. If you would rather not commit red, hold this and commit it together with Task 3.)

---

## Task 3 — ticketed FIFO in `scripts/checks-queue.sh`

File: `scripts/checks-queue.sh`.

**3a. Header comment.** Replace the sentence `This takes a machine-wide lock first and waits its turn, saying who holds it;` with `This takes a ticket, waits for the lowest live one (first come, first served), then takes the machine-wide lock, saying who holds it;` keeping the rest of that comment line intact.

**3b. Replace** the block from `# the office's rack reads the holder and the waiters (Server.Office.Room.checks/0)` through the closing `fi` (the whole `if ! flock -n 9; then … fi`) with exactly:

```bash
# FIFO: a ticket, then the lock only for the lowest live ticket. The lock (the kernel's flock) still
# does the mutual exclusion; the tickets only decide who may try it, so a newcomer never beats a
# waiter. The office's rack reads the holder and the waiters (Server.Office.Room.checks/0).
wait_dir="$dir/tlon-checks.wait"
seq_file="$dir/tlon-checks.seq"
poll="${CHECKS_POLL:-0.5}"

# alive <pid>: a running checks-queue.sh (the cmdline guard keeps a reused pid from holding the line)
alive() { [ "$1" = "$$" ] || { [ -r "/proc/$1/cmdline" ] && tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q 'checks-queue\.sh'; }; }

# take_ticket: the next number, and the entry <10-digit ticket>-<pid> written under the same lock, so
# no ticket is ever taken but invisible. Prints the entry's path; fails if the bookkeeping can't be written.
take_ticket() {
  mkdir -p "$wait_dir" || return 1
  (
    exec 8>>"$seq_file" || exit 1
    flock 8 || exit 1
    n="$(cat "$seq_file" 2>/dev/null)"
    n=$((10#${n:-0} + 1))
    printf '%d\n' "$n" >"$seq_file" || exit 1
    entry="$wait_dir/$(printf '%010d' "$n")-$$"
    printf '%s\n' "$me" >"$entry" || exit 1
    printf '%s' "$entry"
  )
}

if entry="$(take_ticket 2>/dev/null)" && [ -n "$entry" ]; then
  trap 'rm -f "$entry"' EXIT
  told=0
  while :; do
    head=""
    for f in "$wait_dir"/[0-9]*-[0-9]*; do # padded tickets: glob order is arrival order
      [ -e "$f" ] || continue
      if alive "${f##*-}"; then head="$f"; break; fi
      rm -f "$f" # a dead waiter's ticket: whoever notices removes it
    done
    if [ "$head" = "$entry" ] && flock -n 9; then break; fi
    if [ "$told" = 0 ]; then
      echo "checks queue: waiting — $(cat "$holder" 2>/dev/null || echo 'another check is running')" >&2
      told=1
    fi
    sleep "$poll"
  done
  rm -f "$entry"
else
  echo "checks queue: can't write $wait_dir or $seq_file — falling back to a plain lock, no queue order" >&2
  flock 9
fi
```

Everything after it (`echo "$label …" >"$holder"`, the `trap ': >"$holder"' EXIT`, `setsid "$@" 9>&- &`, the TERM/INT traps, `wait "$child"`) stays byte for byte. In the `else` branch there is no entry, so the later EXIT trap is the only one; in the `if` branch the entry is removed before the holder trap replaces the EXIT trap.

Gotchas to keep: `$$` inside the `( … )` subshell is still the script's pid (bash keeps `$$`), which is what the entry must carry. `me` is already defined above the block. `9>&-` on the child is unchanged; fd 8 lives only in the subshell.

**Verify:** `scripts/checks-queue.test.sh` → every line `ok`, exit 0 (run it twice; the race loop must not flake). Plus a manual contended run: `CHECKS_POLL=0.1 scripts/checks-queue.sh sleep 3 & sleep 0.3; scripts/checks-queue.sh echo second` prints `checks queue: waiting — … (pid N) …` then `second`, and `ls $XDG_RUNTIME_DIR/tlon-checks.wait` is empty afterwards.

Also confirm the spec's open item: the cmdline guard holds for every caller. `grep -rn "checks-queue" scripts tasks mise.toml` and check each caller reaches the script as `bash …/checks-queue.sh` or by shebang (`scripts/check.sh`, `scripts/run-from-root.sh` if it wraps it); any `exec`-via-wrapper keeps the name in cmdline. If a caller renames argv0, say so on the thread instead of weakening the guard.

Commit: `scripts: checks queue is FIFO — a ticket, then the lock only for the lowest live ticket`.

---

## Task 4 — wire the test into the gate, keep docs true

Files: `tasks/server.toml`, `AGENTS.md`, `docs/manual/tasks.md`.

- `tasks/server.toml` task `check:names`: `run = "scripts/check-names.sh && scripts/check-glossary.test.sh && scripts/scratch.test.sh && scripts/checks-queue.test.sh"`; in its `description`, after "scratch.sh prune keeps exactly the unlanded work" add ", checks-queue.sh runs waiters first come first served".
- `AGENTS.md`, the `mise run check` bullet: after "it waits its turn in the checks queue (`scripts/checks-queue.sh`, saying who holds it)" add ", first come, first served,".
- `docs/manual/tasks.md`: the `check:names` row mirrors the task description; if `mise run check:names` flags the manual out of sync, update that row to the new description as its message says.

**Done:** `mise run check:names` green (it runs the new test, ~10 s). Commit: `check:names runs the checks-queue self-test; AGENTS.md says the queue is FIFO`.

---

## Task 5 — verify and hand off

1. `menard run test --in server test/server/office/room_test.exs`
2. `scripts/checks-queue.test.sh` (twice)
3. `mise run check:names`
4. `menard run check --in server` (a seat has no checks queue or Postgres: verify runs the full `mise run check` on the server — and that run goes through *this* script, so it is the first real use of it; watch for it waiting and then running).
5. Record each with `record_check`, then `advance_stage`.

**Definition of done for A:** the FIFO cases pass, including C arriving as the slot frees (20 rounds); a killed waiter does not block the line; `Room.checks/0` still reads holder and waiters, now in ticket order; traps, `9>&-`, exit 2 / 143 / 130 and `CHECKS_UNQUEUED` untouched. B consumes the entry format `^\d{10}-\d+$` and the holder file as they are.
