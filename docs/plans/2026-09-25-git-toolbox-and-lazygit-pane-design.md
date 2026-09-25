# A git toolbox for agents + lazygit beside the thread — design

**Date:** 2026-09-25
**Status:** designed; nothing built. Sequenced in §5, each step gated by a check.
**Asked:** Andrew, on Claude Code's changed-files panel: *"let's steal it, but put lazygit there
instead of just the thin claude code changed files view. and let's build a way for claude code and
friends to … drive lazygit around and make patches and shit. A menardalike that forces all git stuff
to go through lazygit maybe."*

---

## 0 · The call

Two pieces that meet in the working tree, not in each other:

1. **The pane** — in a thread, the cockpit keeps lazygit open beside the conversation, on the
   thread's worktree. It is the human's view and the human's hands.
2. **The toolbox** — agents do git through a small set of verbs (stage a hunk, split a commit,
   commit with the thread trailer, fixup, reword …) served over MCP, with a guard that refuses raw
   `git` writes in Bash. The menard shape, for git.

The agent never drives lazygit. lazygit has no API: driving it means sending keystrokes and reading
the screen back, and its modal states (a confirm box, a filter, a staging view) turn every script
into a guess. Instead both act on the same repo: an agent's verb changes the index or the history,
and lazygit shows it within two seconds (`git.autoDetectExternalChanges`, checked every
`refresher.externalChangeCheckInterval: 2`). You watch the agent work in lazygit, and you can reach
in and fix a hunk yourself in the same pane.

MCP, not ACP: MCP is how Claude Code and pi both take tools. ACP is for an editor hosting an agent,
which is not this.

## 1 · The pane

What exists: `Console.Lazygit` builds the command, and the STACK zoom opens lazygit full-frame in a
`Console.Terminal` PTY on `Server.Worktree`'s checkout (`cockpit.ex` `open_lazygit/1`). It is a
zoom you open and close.

What changes: in a thread, lazygit lives in a **right-hand column** beside the conversation, the
place Claude Code puts its changed-files list. It opens on the thread's worktree when the thread
has one, stays running while you move around the thread, and is killed when you leave it (the same
`safe_session_ensure({:lazygit, id}, …)` lifecycle, now keyed to the thread view instead of the
zoom).

- Focus moves into it with the existing `Ctrl+Space` TERM↔NAV leader, so no new input model. The
  keymap rule holds: the reply box is persistent, so pane keys are live only while it has focus.
- Narrow frames drop the column and keep the zoom; the width cut-off is decided on the live pass,
  not here.
- A thread with no worktree shows no column.

## 2 · The toolbox

Its own repo, like menard, so it works in any project and on the work Mac. Working name **`pen`**,
after Ts'ui Pên, whose novel in *The Garden of Forking Paths* (in *Ficciones*) is a labyrinth of
branching timelines.

**Three doors onto one library, as menard does it:** a CLI, a stdio MCP server (tools named by
verb), and a guard for each harness — a Claude Code `PreToolUse` hook and a pi extension.

**The verbs.** Every writing verb answers with what it did and the repo's state after it (status +
the affected hunks), so the agent never re-reads to find out. Hunks carry ids so a `diff` answer can
be acted on precisely.

| verb | does |
|---|---|
| `status` | branch, ahead/behind, staged / unstaged / untracked, as data |
| `diff [path] [--staged]` | hunks with ids (`<path>#<n>@<hash of header+body>`); stale ids are refused, not guessed |
| `stage` / `unstage` | a path, a hunk id, or a line range inside a hunk (a built partial patch through `git apply --cached`) |
| `discard` | a hunk or path out of the working tree; refused on anything staged |
| `commit MSG` | commits what is staged; the thread trailers come from the pane's env, as `prepare-commit-msg` already does |
| `amend` / `reword REV MSG` / `fixup REV` | fixup = commit the staged hunks as `fixup!` of REV, then a non-interactive autosquash |
| `split REV` | move named hunks out of REV into a new commit after it |
| `log` / `show REV` | commits as data: subject, trailers, files, hunks |
| `branch` / `switch` | only `work/*` for a coworker; the pre-commit fence already refuses the rest |

**The guard.** Bash calls that write through `git` (`add`, `commit`, `reset`, `restore`,
`checkout -- …`, `rebase`, `merge`, `cherry-pick`, `revert`, `apply`, `am`, `stash`, `rm`, `mv`,
`tag`, `branch -d/-D`, `push`) are refused with the verb to use instead. Reads (`status`, `log`,
`diff`, `show`, `blame`, `rev-parse`) pass. `push` stays with the human for now. A human terminal is
not guarded; only a harness is.

**What it deliberately does not do:** interactive rebase, conflict resolution, anything touching a
remote. Those stay human work in the lazygit pane until a verb proves itself.

## 3 · Where each part lives

- The pane: `tlon/console` (a cockpit feature).
- The toolbox: a new repo, `pen`. tlon's coworker profiles wire it the way they wire menard (the
  MCP in each profile, the guard in the Claude Code launcher and the pi extensions); ficciones' flake
  wires it for the human's own Claude Code and pi, beside `menardRepo`.

## 4 · Language

Elixir, reusing menard's scaffolding: the anubis MCP server, the plugin layout, the guard-hook shape
and the `run`-verb reply format. The price is menard's slow first start (13 s cold); it is paid
once per session, and it keeps one toolchain across the tools. Open to TypeScript/bun if that start
time bites in practice.

## 5 · The sequence

1. **The pane.** lazygit in the thread's right column, TERM↔NAV focus, killed on leaving the thread.
   *Check:* console suite green; a live pass through `drive-cockpit`: open a staffed thread, the
   pane shows its worktree, a file an agent writes shows up in lazygit within 3 s.
2. **`pen` read verbs + `commit`.** `status`, `diff` (hunk ids), `log`, `show`, `commit` with
   trailers, over CLI and MCP.
   *Check:* its own suite green against throwaway repos; a Claude Code coworker commits through
   `commit` and `server:roster`'s thread shows the commit joined by trailer.
3. **Hunk verbs.** `stage`/`unstage` by hunk and line range, `discard`, `fixup`, `split`, `reword`.
   *Check:* suite covers each against a fixture repo, including a stale hunk id being refused.
4. **The guard on.** Claude Code hook + pi extension, wired into tlon's coworker profiles.
   *Check:* a coworker's `git commit` in Bash is refused naming `pen commit`; `git status` passes; a
   human terminal is unaffected.

## 6 · Open

- **The name.** `pen` is a working name.
- **Push.** Human-only for now; a `push` verb (to `work/*` only) once a coworker's commits have
  earned it.
