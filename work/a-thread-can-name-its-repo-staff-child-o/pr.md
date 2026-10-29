`staff_child` and `open_thread` take an optional `repo`, so a thread can work in a sibling repo (menard, ex_compact, …) — closes #473.

`Server.Thread` already carried `repo` and `Projects.repo_for_thread/1` honoured it, but no staffing tool set it, so every Machine-workspace thread resolved to tlon. The new `Projects.workspace_repo/2` accepts only a path some project of the caller's workspace registers (`~`-expanded) and refuses anything else, opening nothing. The worktree and `push_branch` then follow the thread's repo as for any thread; no `push_branch(workspace:)` was added.

Checked: `menard run check --in server` (new tests: workspace_repo, staff_child repo accepted/refused, open_thread accepted/refused).
