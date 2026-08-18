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
- `mise run funes:release` / `funes:restart` / `funes:console` / `funes:logs` — the always-up funes channel: a headless `mix release` kept up by a `systemd --user` service (loopback, real db), and the ways to redeploy/inspect/watch it.
- `mise run home:switch` — install/update this machine into the user profile via home-manager.

mise owns dev runtimes; Nix owns packaging and the system. **If a command belongs in the loop, it becomes
a task in `mise.toml`** — never a prose instruction that drifts out of sync with what actually runs.

### Picking a pi model — the routing, as tasks ("litellm but not")

Two subscriptions, two buckets. The **$100 Claude plan** is the scarce, high-value bucket (5-hour +
weekly caps); the **$20 ollama.com plan** is the flat all-night workhorse. Neither charges per token —
"cost" means *which rate-limited bucket am I draining*, so the rule is: **push work down to the cheapest
bucket that can still do it well.** pi (the harness) rides the ollama bucket; Claude Code is the Claude
bucket — kept as two tools so a switch never drains the wrong one.

Inside the ollama bucket the routing is not a proxy — it's five mise tasks, each a named model profile
(the loop *is* the aliasing layer). Bare `pi` already starts on `ollama-cloud/deepseek-v4-flash` — the
 efficient-MoE default that drains the short rate-limit window far slower than a reasoning model
 (run `mise run ollama:usage` to see the session/weekly caps and per-model request counts); these pin an
alternate, and in-session `Ctrl+P` cycles the same ring. Pass a one-shot with `-- -p "…"`.

| Task | Model | Reach for it when |
|---|---|---|
| `mise run pi:balanced` | glm-5.2 | The strong default — Claude/GPT-alike, 976K ctx. Reach for it when the cheap default can't do the job, before escalating to pi:deep. |
| `mise run pi:deep`     | deepseek-v4-pro `thinking:high` | Hard reasoning/logic — the escalate-before-you'd-miss-Claude tier. |
| `mise run pi:code`     | kimi-k2.7-code | Coding-heavy work; code-specialized, fewer thinking tokens. |
| `mise run pi:fast`     | deepseek-v4-flash `thinking:low` | The same model as the bare default but `thinking:low` — quick/cheap throwaway, 1M ctx, fast tier. |
| `mise run pi:local`    | qwen3-coder (local daemon) | Free/offline grunt, tight iteration loops — zero cloud budget. |

Every launcher also makes the harness a **funes citizen**: it opens a fresh funes thread (or JOINs one
with a trailing id — `mise run pi:code -- 42`) and hands the session its identity, so the model shows up
in `funes:roster` and briefs from the thread. `mise run funes:claude [thread-id]` does the same for
Claude Code (its own MCP adapter, `headersHelper`-authed). If the funes channel is down, the harness
still launches — just not as a citizen.

The bare default is `deepseek-v4-flash`, not glm-5.2, precisely because glm-5.2 is a reasoning model
whose thinking tokens drain the short rate-limit window fast — run `mise run ollama:usage` to watch
the session cap move per model. Two things that bite: **glm-5.2 is a reasoning model** (separate
`reasoning` + `content` fields) — give it token headroom or `content` comes back empty while thinking
eats the budget; and **`kimi-k3` is
deliberately absent** — ollama.com serves it as *extra* usage (HTTP 402), billed per-token on top of the
$20 plan, so it's out of both `flake.nix` and the live Ctrl+P ring. Every model above is plan-covered.

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

- `mise run funes:watch` / `mise run manos:pi:watch` — re-run that module's suite on every change.
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
- **An `AGENTS.md` is born the same way a comment is — when a scope needs context its parent doesn't
  give.** Root holds repo-wide invariants; a module or subapp gets its own when it has distinct law, a
  distinct dev loop, or gotchas that bite (`funes`, `manos` + its adapters, `aleph`). Don't add one per
  folder by reflex — `lib/schemas/`, `test/`, etc. earn a file only once they accumulate a rule a
  weaker model keeps getting wrong; until then that guidance lives in the module's file. Keep every one
  terse and actionable to the same standard as comments: orientation, the exact commands, the law, the
  gotchas, a pointer to the one deeper doc — no lore. Skeleton: **what it is → Law → dev loop → Verify.**
  The tree: `AGENTS.md` (here) · `modules/funes/AGENTS.md` · `modules/aleph/AGENTS.md` ·
  `modules/manos/AGENTS.md` (+ `consult`/`fmt`/`lsp`).
- **Keep docs in sync with the code, in the same commit.** A change that makes a module's `AGENTS.md`
  or a load-bearing comment stale updates it in that change — stale guidance is worse than none,
  because a weaker model trusts it. Nothing mechanical can catch this (staleness is semantic, invisible
  to compile/tests), so it's on you. (The `programs.rbw` comment that survived the rbw→agenix switch
  still describing the old design is the incident this comes from.)
- **Adopt Nix gradually.** home-manager on Arch first, a disposable NixOS VM (`nixos-rebuild build-vm`)
  as the testbed, metal last. Do not propose replacing the OS as a first step.
- **Commit as who you are.** An agent's commit ends with a `Co-Authored-By:` trailer naming the model
  that wrote it — YOUR model, read from the brief's `You are … (pi)` line (or `$PI_MODEL`), never a
  name copied from an example or another model's commit. Format: `Co-Authored-By: <your model> (pi)
  <noreply@ollama.com>` (pi) or `Co-Authored-By: <your model> <noreply@anthropic.com>` (Claude Code).
  `git log` is part of the machine's memory; a commit that hides its author — or names the wrong one —
  lies to it. (The first dogfood branch shipped 7 unattributed machine commits — that's the incident
  this rule comes from.)
- **Sandboxed Bash — phantom dotfiles and unreachable localhost are the sandbox, not the repo.** Both
  harnesses are affected: pi via the `pi-sandbox` extension (`~/.pi/agent/sandbox.json`, seeded at
  `flake.nix`'s `piSandboxSeed`) and Claude Code via its own. pi-sandbox delegates to
  `@carderne/sandbox-runtime`, a fork of Anthropic's, so **the `CLAUDE_CODE_*` and proxy env vars
  inside a pi bash call come from the fork — they are not evidence you're in Claude Code.** Two
  symptoms follow, and neither is a bug to chase:
  - *Phantom untracked dotfiles.* The wrapper bind-mounts over shell-rc / `.gitconfig` / editor paths,
    so `git status` **run inside a bash call** reports `.bashrc`, `.zshrc`, `.gitconfig`, `.env`,
    `.mcp.json`, `.idea`, `.vscode`, … as untracked at the repo root. The tell: `ls -la` shows them
    0-byte `-r--r--r--` (or `crw-rw-rw- 1,3`, a `/dev/null` char device). They don't exist on disk.
    Never `git add`/`rm` them or try to "clean them up".
  - *`127.0.0.1` is not the host's loopback.* bash runs under `bwrap --unshare-net` in a private netns,
    so `curl 127.0.0.1:4041`, `ss -tlnp`, and `systemctl --user` can never see the funes channel —
    **regardless of whether it is up.** `allowLocalBinding` only permits binding *within* that netns.
    External traffic escapes via a socat→unix-socket proxy, but that proxy refuses loopback targets
    with a `403`, so there is no route. Do not conclude "funes is down" from a bash probe; a bash
    probe cannot answer the question. **funes MCP tools still work** — pi makes those calls from its
    own process, outside bubblewrap — so use them, or ask the human to check from the host.

  To get true git state or real host network, disable the sandbox: `Alt+S`, `/sandbox-disable`, or
  relaunch `pi --no-sandbox`.
- **Comments earn their place — load-bearing only.** A comment survives only if it states a non-obvious
  *why* or a real gotcha the code can't. Narrative, lore, dated incident references, decorative
  `# --- section ---` dividers, and restatements of what the next line plainly does are noise — don't
  write them, and trim them when you touch a file. Prose belongs in docstrings (`@moduledoc`/`@doc`/
  `@spec`, JSDoc) and the `*.md` files; inline comments are load-bearing only. (A repo-wide pass cut
  ~320 comment lines to this standard — don't grow them back.)
- **Secrets: agenix for the machine, rbw for you.** A secret a non-interactive process needs — a
  service, a spawned pane (e.g. `OLLAMA_API_KEY` for the Tlön pi) — lives age-encrypted in
  `secrets/*.age` (agenix), decrypted at `home:switch` to `$XDG_RUNTIME_DIR/agenix/<name>` with *no*
  runtime unlock. Human/interactive passwords live in Bitwarden via `rbw`. Never a plaintext key in the
  repo, a dotfile, or the nix store. To add a machine secret: recipient pubkey → `secrets/secrets.nix`,
  `agenix -e secrets/<name>.age`, `git add` it (nix can't see untracked files), reference it via
  `age.secrets` in `flake.nix`.

## Verify

`funes` day-one step 1 exists and runs; verify with `mise run check` (tests + types) and `mise run
flake:check` (Nix). A claim that something works is backed by the command that proved it — and the agent
and human run the *same* `mise` tasks, so "it works" means the shared task passed, not two private ones.
