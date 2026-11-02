One writer per worktree: a lobby session never builds or commits in another thread's worktree. Closes #804.

**What changed**
- `Server.Profiles`' shared lobby line now reads: a lobby session answers and advances a thread it leads over MCP (`post_message`, `advance_stage`, `push_branch`, `catch_up_branch`, `submit_review` with `thread_id`); it never builds or commits in another thread's worktree, and the hand-off brief seats the thread pane that does. The old line told it to commit in the workline's worktree.
- `scripts/git-hooks/pre-commit` refuses every commit from a `TLON_LOBBY` pane, not only one on `work/t<lobby>`. The `work/uqbar-*` allowance from the lobby was dead: Uqbar's pane runs on its study, never the workspace's root thread, so it never carries `TLON_LOBBY` (`Server.MCP.Spawn.lobby_export/1`).
- `Switchboard` and `Wake` are unchanged: the wake was right. A pin in `switchboard_test.exs` shows the trigger — a non-lead `@mention` wakes the coworker's lobby window, the hand-off that follows spawns a pane on the thread with no `TLON_LOBBY`, and the lobby session stays live. The licence, not the wake, keeps one writer per worktree.
- Two more pins from the review's grade: a shift switch restaffs a workline led by an off-shift builder, so its wake seats the stand-in on the thread (no `TLON_LOBBY`), never in the lobby — the lobby stand-in path is for plain threads, whose stand-in never builds; and Uqbar's study pane carries no `TLON_LOBBY`. The study test now opens the lobby first, as boot does (`Bootstrap.ensure_standing/1` before `Outside.ensure_checkin/1`): in a workspace with no lobby the study would itself be the oldest machine thread, so the root.

**Why**
On #710 (thread 520) two sonny sessions built in one worktree: the lobby one, woken by Uqbar's `@sonny` at review stage, and the thread pane seated by `send_back`'s hand-off. Both were licensed by the brief and by the hook.

**How it was checked**
- RED first: the Profiles test failed on the builder prompt (no such line), the commits test on `work/710-the-workline` committing from a lobby pane; the Switchboard test reproduced the two-session state.
- GREEN: `profiles_test.exs`, `commits_test.exs`, `switchboard_test.exs`, `mcp/spawn_test.exs` — 171 passed. After the send-back: `switchboard_test.exs` 61 passed (the study refute was red until the lobby came first).
- `server:check` on the committed head via `run_task`: result on the thread.

Out of scope, filed by tertius: narrowing the lobby seat's sandbox write list to its own worktree.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
