# server

> "To think is to forget differences, to generalize, to abstract."
> — Borges, *Funes the Memorious*

Ireneo Funes fell off a horse and woke unable to forget anything. He could reconstruct a whole day
in perfect detail, and it took him a day. This module is named after him as a warning to itself. It
is Tlön's spine, the memory and coordination layer between the office (`../office`), the agents that
reach it over MCP (`../adapters`) and the work in your repos, and its specification is an argument
against being Funes: remember carefully, not completely; rank and cut everything; a surface that is
complete is not one that answers a question.

**Read `docs/spec.md` before writing anything here.** Every rule in it names the failure that paid
for it; `docs/spec-review.md` and `docs/v1-review.md` are the adversarial reviews it survived. If
this README contradicts the spec, the spec wins.

## What is here

| | |
|---|---|
| `docs/spec.md` | the specification; `spec-review.md` and `v1-review.md` the reviews that shaped it; `issues.md` the bootstrap issue list |
| `lib/server.ex` | the public surface: its `exports:` list is everything a consumer may call |
| `lib/server/` | the contexts: `Channel` (threads, messages), `Staff` and `Crew`, `Dossier`, `Board`, `Workspaces`, `Projects`, `Tickets`, `Notes`, `Switchboard` + `Bus` + `Arbiter` (a delivery wakes its addressee), `MCP.*` (the agents' channel), `Workline`, `Recall`, `Office`, `Release`, `Seed` + `Bootstrap`, `Doctor` |
| `lib/mix/tasks/` | `server.doctor`, `server.seed`, `server.eval`, `server.bench_roles`, `server.ledger`, and the imports |
| `priv/repo/migrations/`, `priv/seed/` | the schema, and the base knowledge applied on every boot |
| `rel/` | the burrito release: one executable with the runtime inside |

## The one architectural decision

Three owners, no overlap:

- **Postgres** holds the truth: facts, events, issues, the channel, the containers.
- **tmux** (a private server per workspace) holds the terminal's truth: windows, panes, which agent
  is live.
- **Agents** hold nothing durable: they reach the spine only through the MCP channel, and what they
  learn is banked here or lost.

If the split is wrong, most of this is wrong.

## Deliberately not built

A meta-orchestrator session. Mode-switch keybindings. A second log or a dual write. Mirrored
terminal state. Metrics that never changed a decision. Hand-authored machine documentation. A
taxonomy on what may be posted to the channel. `docs/spec.md` §10 says why each is out, with the
measurement.

## Working on it

`AGENTS.md` is the law and the dev loop: the mise tasks, the gate (`mise run server:check`), the
always-up service and how to redeploy it. A change is built in a scratch worktree
(`mise run scratch:new -- NAME origin/main`), never in the live checkout. `mix server.doctor` is the
repair tool: nothing ships that cannot be fixed at 2am.
