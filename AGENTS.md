# ficciones — boundaries for a session at the repo root

This repository is one person's whole machine: an installer, dotfiles, a desktop, and an AI stack, as
Nix-shaped modules under `modules/`. It is named *ficciones* after the Borges collection that contains
the "Funes" story — the repo contains the `funes` module as the book contains the story, and each module
is another story. Read `docs/plans/2026-08-14-machine-v2-and-funes-design.md` before reshaping anything
here — it is the design and every decision behind it.

## The dev loop — one shared API

The human and any agent drive this repo through the **same mise tasks** (`mise tasks` lists them) — one
control loop, not two, and no second way to run anything:

- `mise run check` — funes compile-clean + tests; the green-before-commit gate.
- `mise run funes:test` / `funes:check` / `funes:setup` / `funes:doctor` — the funes loop (Elixir/mix).
- `mise run flake:check` — the machine-level Nix gate.
- `mise run home:switch` — install/update this machine into the user profile via home-manager.

mise owns dev runtimes; Nix owns packaging and the system. **If a command belongs in the loop, it becomes
a task in `mise.toml`** — never a prose instruction that drifts out of sync with what actually runs.

### Run once, read the log — never re-run to see more

When you run a command whose output you'll inspect — a test suite, a build, a `scratchpad`
script — run it through **`scripts/cap.sh`** (or `mise run cap -- <cmd>`). It runs the command
**once**, captures all output to a log under `.logs/`, and prints a lean summary: the exit code,
a test/build-summary line, failure lines on a non-zero exit, and a short tail — plus the exact
`tail`/`grep` to read more **from the saved log**.

The rule this enforces: **do not re-run a command with an escalating `grep … | tail -N` to see
more of its output.** The full output is already on disk — `grep`/`tail` the log. Re-running
burns tokens, re-streams noise into context, and risks a slightly-different invocation each time.
Catching yourself about to run the same command a second time with a different filter is the
signal to read the log, not repeat the call — the same escape hatch any SWE reaches for when a
loop starts repeating itself.

`cap` prints a distilled **signal** view (results, errors, warnings, counts) and drops the
install/compile/debug noise; a green suite collapses to a couple of lines. Knobs when you need
them: `CAP_TAIL=all` (the whole log inline, once), `CAP_TAIL=<n>`, `CAP_SIGNAL=<n>`. `mise run
cap:clean` sweeps the logs (they self-cap at 40 anyway).

### Let the watcher run the tests — don't spend a turn doing it by hand

When you're iterating on a change, **register a watcher instead of re-running tests yourself**:

- `mise run funes:watch` / `mise run pi:watch` — re-run that module's suite on every change.
- `scripts/watch.sh <cmd>` (or `mise run watch -- <cmd>`) — watch-and-run anything, any scope
  (one test file, a folder, the whole suite). New test files under a watched dir are picked up.

Run it **in the background** (this harness: `Bash` with `run_in_background` — you're re-invoked
with the result when the suite settles; pi: a pane). Then just edit: you're pinged **red/green
automatically**, and you only spend a turn when something actually breaks. Kill the watcher when
the change is done. This is the intended inner loop here — not "edit, then manually run tests,
then read 1800 lines," every time.

## The rules most likely to be broken by accident

- **Working inside `modules/funes/`? That module has its own law.** Read `modules/funes/AGENTS.md` and
  `modules/funes/docs/spec.md` first, and let them win. This root file governs the layer *around* the
  modules, not the modules' insides.
- **`funes` is a bounded module and the boundary is load-bearing.** It must never import up into machine
  config — no reading a `theme` variable, no assuming `desktop`, no path into `hosts/`. The reason is the
  cohesion model: the *same* `funes` runs on other machines, sovereign on each, talking only over its
  channel. A reach upward welds it to this box and breaks that. The unit that travels is `modules/funes/`.
- **`nix` runs from the agent tools now** (Arch's nix, not Determinate — see the Nix machine-truth
  memory). So `nix flake check`, `nix eval`, and `nix build .#funes` are fair to run and verify directly.
  What stays the human's are the **system-mutating** commands — `home-manager switch`, `nixos-rebuild
  switch` on the host — because building the machine is a change the human owns. A claim that a build
  works without having run it is the one thing this repo cannot afford.
- **A module is born when it has content.** Do not create empty placeholder directories to imply a
  structure that does not exist yet. The tree should not lie about what is built.
- **Adopt Nix gradually.** home-manager on Arch first, a disposable NixOS VM (`nixos-rebuild build-vm`)
  as the testbed, metal last. Do not propose replacing the OS as a first step.

## Verify

`funes` day-one step 1 exists and runs; verify with `mise run check` (tests + types) and `mise run
flake:check` (Nix). A claim that something works is backed by the command that proved it — and the agent
and human run the *same* `mise` tasks, so "it works" means the shared task passed, not two private ones.
