# adapters/reload — restart the pi harness, resume the session

One tool, `reload`, for the dogfood loop. pi loads its extensions **once, at process start**, so
when you edit your own tooling (any `adapters/**` extension) the running pi keeps executing
the *old* code. And an agent can't restart the process it lives in and keep its train of thought.
`reload` closes that gap: it respawns pi in place and **resumes the current session**, so you edit
code → call `reload` → wake up in the same thread running the new code.

## When to use it

- After you change a adapters extension's source and want it live **now**.
- NOT for config that pi reads per-run, and NOT a substitute for `console:reset` — this restarts
  *pi*, not the cockpit BEAM or the tmux session.

## How it works

- The coworker launcher (`console` `Cockpit.profile_launcher/3`) exports two things into the session:
  `TMUX_PANE` (pi's own pane, tmux-provided) and **`ADAPTERS_RELOAD_CMD`** — the command that
  re-launches pi with `--continue` (resume the most-recent session = this one).
- `reload` fires a **detached** helper that, after ~0.4s, runs `tmux respawn-pane -k` on pi's pane.
  The delay lets this turn's result flush to the session `.jsonl`; `-k` kills the old pi; the
  launcher's `--continue` brings the thread back. The helper is detached (its own process group)
  so it survives the very process — pi — that spawned it being killed.
- **Gate:** unless `force: true`, it first runs `mise run adapters:typecheck` — every adapters extension
  must typecheck, or a fresh pi could fail to load one and lock you out. On failure it refuses and
  returns the errors.

If `ADAPTERS_RELOAD_CMD` or `TMUX_PANE` is unset, `reload` refuses with a message pointing at the
launcher — reboot the cockpit after updating console so the session carries the export.

## The seam

`planReload(env)` in `src/extension.ts` is pure: given `{ pane, cmd }` it returns either a refusal
reason or the exact detached-respawn argv (pane + cmd passed as positional `$0`/`$1`, never
interpolated — the quoting-safety point). That's what the unit suite pins; the spawn + gate are
the thin live wrapper. `src/pi.ts` hand-declares the registerTool slice (typebox is the one
external import), the adapters idiom.

## Verify

`mise run adapters:reload:check` (install frozen + typecheck + tests). End-to-end is a live dogfood:
edit a adapters extension, call `reload` in the tlön terminal, confirm the change is active after pi
comes back (`ps -eo pid,lstart,cmd | grep bin/pi` — a fresh start time).
