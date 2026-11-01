# Review — staff-child-repo-ficciones-refused-not-a (3c42c3e)

**Verdict: APPROVE.**

Reviewed: the one commit on `work/staff-child-repo-ficciones-refused-not-a` (3c42c3e, `server/lib/server/projects.ex`, `server/test/server/projects_test.exs`, `pr.md`). No spec.md/plan.md: the workline started at build, so none owed. CHECKS: `mise run check` exit 0 (verify, 2026-11-01T05:35:38Z); no `bench_contrast` row, so nothing to contrast.

## The witness

The old `workspace_repo/2` compared `Path.expand(path)` against each registered repo's expanded `"path"` and nothing else. `repo: "ficciones"` expanded to `<cwd>/ficciones` and was refused. The change collects every project's repos with a binary `"path"`, keeps the exact path match first, then falls back to `&1["name"] == path`, returning that repo's expanded path.

## Findings

1. **The fix lands on the live data, not just the test's.** The test registers `%{"name" => "ficciones", "path" => "~/projects/ficciones"}` by hand; what matters is whether the Machine workspace's projects carry short names. They do: `Server.Seed.project_attrs` (seed.ex:253-255) writes every seeded project repo as `%{"name" => Path.basename(path), "path" => path}`, and the machine seed lists `~/projects/ficciones` under a project. So the ticket's repro (`staff_child(repo: "ficciones")` from #1) resolves after this lands. Verified by reading the seed and the live `list_workspaces` scope, not by running the tool against the service.

2. **The ticket's probable cause was wrong, and the fix is right anyway.** The ticket guessed the check read the thread's project repos rather than the workspace's. `in_workspace/1` already flattens every project in the workspace; the real fault was name-vs-path, which is what emma fixed. The error text still says "not a repo of this workspace", which is now accurate for both a bad path and a bad name.

3. **Path match keeps precedence over name.** `cond` tries the expanded-path equality first, so a caller who passes a path that happens to equal some other repo's short name gets the path. Correct ordering.

4. **Test is red-then-green for the right reason.** The new case asserts `{:ok, ^expanded}` for the name and `{:error, _}` for an unknown name; the existing path/`/srv/x` cases are untouched. mcp/server_test's two `"not a repo of this workspace"` assertions still pass under the full gate.

## Non-blocking (follow_ups below)

- Bootstrap's default project names each repo by its full path (`bootstrap.ex:179-180`, `"name" => &1.path`), while the seed names by basename. On a box with no machine seed, `repo: "ficciones"` is still refused; `repo: "~/projects/ficciones"` works. One-line change to `Path.basename/1`.
- The `repo` field descriptions on `open_thread`/`staff_child` (coordination.ex:15, 78) say "the registered repo"; now that a name is accepted they could say "by name or path" so a caller doesn't guess a path.
- The "seen again" on #775 (read-only `~/.cache/tlon-scratch/<seat>`) is a different fault this change does not touch; filed as its own ticket so #775 closing doesn't lose it.

— lonnrot