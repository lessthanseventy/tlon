# tlon

**The name.** Borges' *Ficciones* (1944) names the machine this grew up on; this repo is named for
one story in it: **Tlön**, from "Tlön, Uqbar, Orbis Tertius" (1940), where scholars find an encyclopedia of
an invented planet and, as they study the fiction, it bleeds into reality and overwrites it. That is
exactly what the product does — you author a fictional organization (a cast of agents, workspaces,
knobs) and, through use, it becomes real work in your actual repo. The fiction overwrites reality.

Tlön is **many UIs over one memory** — a communication, planning, and coordination surface for a crew
of AI agents. Four internal apps make it up, named for what they do:

- **`server`** — the shared spine: the data model, the communication bus, the single-writer discipline,
  the always-up MCP channel. (The memory concept is *Funes the Memorious* — the man who could not
  forget — living on in the recall engine.)
- **`office`** — the pixel-art room over the spine, in your terminal: coworkers at their desks when
  they work, queued at your door when a thread waits on you, the worklines on the whiteboard, Nina the
  cat. Click or key into anyone to read their thread and reply.
- **`console`** — the TTY cockpit: workspaces, threads, the crew, embedded terminals. Being folded
  into the office.
- **`adapters`** — the hands: how a working agent (Claude Code, pi) reaches the spine, wakes up already
  knowing its thread, and banks what it learns.

A **workspace** is a project inside Tlön (*ficciones*, the machine, is one). The crew keep their Borges
names — **tertius** (the Orbis Tertius meta-agent), **hronir** (the builder). Cute names only for
things with personality; everything else is called what it is.

## Install

One self-contained executable per platform, from the
[releases](https://github.com/lessthanseventy/tlon/releases): `tlon_linux_x64`, `tlon_linux_arm64`,
`tlon_macos_arm64`, `tlon_macos_x64`. The server, its runtime and the office TUI are all inside.

```sh
curl -L -o tlon https://github.com/lessthanseventy/tlon/releases/latest/download/tlon_linux_x64
chmod +x tlon && mv tlon ~/.local/bin/
```

**macOS:** the executables are not signed, so Gatekeeper quarantines a download; clear it once with
`xattr -d com.apple.quarantine ~/.local/bin/tlon`. (The macOS builds are cross-compiled and have not
yet been run on a Mac — reports welcome.)

It needs, on the same machine:

- **Postgres**, with a database your user reaches over the local socket: `createdb tlon`. (Homebrew's
  socket is `/tmp`, Linux packages' `/run/postgresql`; `PGHOST` names another,
  `TLON_DATABASE_URL` a remote one with a password.)
- **tmux** — the crew's terminals live in it.
- For the office's art, a terminal with the kitty graphics protocol (ghostty, kitty, WezTerm). Others
  get the room in half blocks.

## Quickstart

```sh
export TLON_OPERATOR=yourname   # who you are on the channel (the default is "andrew")
tlon                            # migrates the database, then serves on 127.0.0.1:4040
tlon office                     # in another terminal: the office
```

The server is loopback-only. The office talks to it over HTTP (`TLON_URL` points it elsewhere); the
agents talk to it over MCP at `http://127.0.0.1:4040/mcp`.

## Configuration

All environment, read at start:

| Variable | Default | |
|---|---|---|
| `TLON_OPERATOR` | `andrew` | your handle |
| `TLON_DATABASE` / `TLON_DATABASE_URL` | `tlon` | the store |
| `TLON_MCP_PORT` | `4040` | the channel (MCP + the office's HTTP API) |
| `TLON_WEB_PORT` | `4042` | the web UI |
| `TLON_START_WEB`, `TLON_START_MCP`, `TLON_START_OBAN`, `TLON_START_SWITCHBOARD`, `TLON_START_ATTENTION` | on | the services, each switchable off with `0` |
| `TLON_WORKLINE_ROOT` | the cwd | the checkout workline checks run git in |
| `TLON_URL` | `http://127.0.0.1:4040` | (office) the server to talk to |
| `TLON_PALETTE` | `~/.config/tlon/palette.json` | (office) your desktop's colours, `{ "role": { … } }`, followed live |

## From a checkout

```
tlon/
  server/     # the spine — its own spec (server/docs/spec.md), its own boundary
  office/     # the pixel-art room: a shared kit, its rooms, the TUI
  console/    # the TTY cockpit
  adapters/   # the hands: pi extensions, the Claude Code launcher + hooks, skills
  tasks/      # the mise tasks (mise.toml includes them) — `mise tasks` lists every verb
  scripts/    # the shell side of the loop (cap, watch, the reaper, the tlon CLI)
```

[mise](https://mise.jdx.dev) brings the toolchains (Erlang, Elixir, bun). `mise run server:setup` once,
`mise run office:run` for the office over a running server, `mise run server:package` to build the
executables above. Start with `AGENTS.md`; the gate is `mise run check`.
