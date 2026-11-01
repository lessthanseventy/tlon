staff_child / open_thread `repo` now accepts a registered repo's name (e.g. `ficciones`), not only its path.

Why: `Projects.workspace_repo/2` compared only paths, so `repo: "ficciones"` expanded against the cwd and was refused "not a repo of this workspace" although the workspace registers it. Closes ticket #775.

Checked: new `projects_test` case (red: refused; green: resolves to the expanded path); `projects_test` 25/25 and `mcp/server_test` 110/110 green via `menard run test --in server`.
