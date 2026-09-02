# server

> "He knew the forms of the clouds in the southern sky on the morning of April 30th, 1882, and he could
> compare them in his memory with the veins in the marbled binding of a book he had seen only once…
> He was, let us not forget, almost incapable of ideas of a general, Platonic sort. To think is to
> forget differences, to generalize, to abstract."
> — Borges, *Funes the Memorious*

Ireneo Funes fell off a horse and woke up unable to forget anything. He could reconstruct every day of
his life in perfect detail; each reconstruction took a full day. He found it hard to sleep, because he
could not stop perceiving. He was not, in any useful sense, able to think.

This module is named after him as a warning to itself. It is Tlön's spine — the memory and coordination
layer between the cockpit (`../console`), the agents that reach it over MCP (`../adapters`: Claude Code,
[pi](https://github.com/earendil-works/pi-coding-agent)), and the work — and its entire specification is
an argument against being Funes. It remembers
carefully rather than completely: the always-loaded set is 32 rows, not 297; a surface that is *complete*
is not one that *answers a question*; rank and cut everything. A system that could not forget would be
correct and useless, which was the exact verdict on the thing this replaces.

**Read `docs/spec.md` before writing anything here.** Every rule in it names the failure that paid for
it, and it was reviewed adversarially twice. If something in this README contradicts the spec, the spec
wins.

## A module, with a boundary

`server` lives inside a larger `machine` repository (`../../README.md`) but does not belong to it. It
never reaches up into machine config — no theme, no desktop, no host paths — because the *same* `server`
is meant to run on other machines, sovereign on each, and the machines "know about each other" only by
talking over its channel, never by sharing state. The unit that travels to another machine is this
directory. That boundary is the spec's §8c, redrawn one level in; the 2026-08-14 amendment at the top of
the spec records why.

## What is here

| File | What it is |
|---|---|
| `docs/spec.md` | The specification. Every rule names the failure that paid for it. |
| `docs/spec-review.md` | A fresh session's adversarial review of the spec, which found seven defects. Kept because the arguments are the reasoning. |
| `docs/v1-review.md` | An adversarial review of **version one** — what made a version two worth specifying. |
| `docs/issues.md` | The bootstrap issue list from before the `issue` table existed. Historical. |
| `lib/server.ex` | The public surface: the `exports:` list is everything a consumer may call. |
| `lib/server/` | The contexts — `Channel` (threads, messages), `Staff`, `Dossier`, `Board`, the container tier (`Workspaces`, `Projects`, `Tickets`, `Notes`), `Switchboard` + `Bus` + `Arbiter` (delivery wakes the addressee), `MCP.*` (the agents' channel), `Workline`, `Recall`, `Seed` + `Bootstrap`, `Doctor`. |
| `priv/repo/migrations/`, `priv/seed/` | The schema, and the wipe-proof base knowledge applied on every boot. |
| `rel/` | The headless release the `systemd --user` service runs. |

## The one architectural decision

Three owners, no overlap:

- **SQLite** holds the machine's truth — facts, events, issues, the channel, the containers.
- **The cockpit, over tmux** holds the terminal's truth — windows, panes, focus, which agent is live.
- **Agents** hold nothing durable: they reach the spine only through the MCP channel, and what they
  learn is banked here or lost.

If the split is wrong, most of this is wrong.

## Deliberately not built

A meta-orchestrator session. Mode-switch keybindings. A second log or a dual write. Mirrored terminal
state. Metrics that never changed a decision. Hand-authored machine documentation. A taxonomy on what
may be posted to the channel. See `docs/spec.md` §10 for why each is out, with the measurement.

## Working on it

`AGENTS.md` here is the law and the dev loop: the `mise` tasks, the gate (`mise run server:check`),
the always-up service and how to redeploy it. The first thing built was the database plus a repair
tool (`mix server.doctor`) — nothing ships that cannot be fixed at 2am. Funes remembered everything
and could fix nothing; this does the opposite on purpose.
