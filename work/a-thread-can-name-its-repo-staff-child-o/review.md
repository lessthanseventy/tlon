# Review — a-thread-can-name-its-repo-staff-child-o @ 0079a73

**Verdict: request_changes.** One blocking bug on the path the ticket exists for; the rest is sound.

## Findings

**1. BLOCKING — a workline child silently loses its `repo`.**
`StaffChild.open_child/4` merges `repo` into the attrs for `Server.Workline.open_titled/3`, but `Workline.open/1` inserts through `Thread.workline_changeset/1`, whose cast list is `[:title, :scope, :slug, :born, :workspace_id, :project_id, :parent_thread_id, :stage]` — no `:repo`. Measured:

```
cd server && MIX_ENV=test mix run --no-start -e 'IO.inspect(Server.Thread.workline_changeset(%{title: "x", slug: "x", stage: "build", repo: "/home/andrew/projects/menard", workspace_id: 1}).changes)'
%{scope: "machine", title: "x", stage: "build", workspace_id: 1, slug: "x", born: "operator", created_at: ~U[2026-10-29 01:41:18Z]}
```

Consequence: `staff_child(workline: "build", repo: "~/projects/menard")` opens a workline whose `repo` is nil; `repo_for_thread/1` falls through to the parent's project and resolves to tlon; its worktree lands under tlon and `push_branch` pushes `work/<slug>` to tlon. That is ticket #473's own case. The three new tests all take the plain-thread path (`Thread.open_changeset/1` does cast `:repo`), so none of them sees it.

Fix (two lines plus a test):

```
--- a/server/lib/server/thread.ex
+++ b/server/lib/server/thread.ex
@@ workline_changeset
       :workspace_id,
       :project_id,
+      :repo,
       :parent_thread_id,
       :stage
```

and in `server/test/server/mcp/server_test.exs`, describe "staff_child repo":

```
    test "a workline child keeps the repo too", %{rtoken: token, rsession: session} do
      r =
        call(token, session, 7, "staff_child", %{
          "title" => "menard build",
          "lead" => "hronir-repo",
          "brief" => "Build it.",
          "repo" => "~/projects/menard",
          "workline" => "build"
        })

      refute r["isError"]
      assert Repo.get!(Thread, decode_tool_json(r)["thread_id"]).repo == Path.expand("~/projects/menard")
    end
```

Run the test before the cast change to see it red.

**2. Nit, non-blocking — the tests stop one hop short of the spec.** The brief asked that a sibling-repo thread "ensures its worktree under that repo, and push_branch runs `git -C <that repo> push`". The tests assert `Server.repo_for_thread/1`. I verified by reading that `Server.worktree_for_thread/1` (`repo_and_name/1`) and `PushBranch.execute/2` both resolve through it, so the hop is existing code; an assertion on `Server.worktree_for_thread(tid)` returning `{:ok, <menard>/.worktrees/<slug>}` would make the claim measured. Cheap if you are in the file anyway.

## Verified sound
- `Projects.workspace_repo/2`: `Path.expand` both sides, exact match against every project of the workspace, so a trailing slash or `~` form matches and `/etc` is refused; a glob scope entry can never match (safe side). Checked before anything opens in both tools; the refused-opens-nothing test covers it.
- `repo_attrs/2` falls back to `Bootstrap.default_workspace_id/0` for a caller with no thread or workspace; `Channel.open_thread/1` already defaults `workspace_id` the same way, so adding it is consistent.
- `push_branch` is unchanged and still `Server.repo_for_thread/1` on every path; no `push_branch(workspace:)` was added, as the brief required.
- CHECKS: `menard run check --in server` 2391/0 and the server's `mise run check` both green on 0079a73. No `bench_contrast` row, so nothing to call there.

## Follow-up (not this diff's lines)
See follow_ups: the brief's claim that the server sets `core.hooksPath` on a sibling repo's worktree is not true of the code, so sibling-repo commits carry no `Tlon-Thread`/`Tlon-Model` stamp and the seat's own `git push` is unfenced. hronir's call whether it gates staffing sibling threads.