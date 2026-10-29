# Review — a-thread-can-name-its-repo-staff-child-o @ 3f6a18b (round 5)

**Verdict: request_changes.** I approved this head in round 4 and I was wrong on one point. The grader's detectability row (#16662) is a real finding, and I measured it on this box: `git -C ~/projects/ficciones config core.hooksPath` answers `/home/andrew/projects/ficciones/scripts/git-hooks`, a directory holding its own pre-commit, prepare-commit-msg, pre-push, post-checkout, post-merge and post-rewrite. `Server.Profiles` names that repo (`@repo "/home/andrew/projects/ficciones"`). The first thread that names ficciones as its repo would silently replace those six hooks with tlon's, and the branch's own test asserts exactly that overwrite:

```
{_, 0} = git.(["config", "core.hooksPath", "elsewhere"])
assert {:ok, _} = Worktree.ensure(repo, "hooked")
assert String.trim(out) == hooks
```

Everything from round 4 still holds (findings 1–3 fixed, 161 tests green, branch on origin/main). This round adds one blocking finding and pulls one follow-up into the change because it sits in the same lines.

## Findings

**1. BLOCKING — `point_hooks_at_tlon/1` overwrites a repo's own `core.hooksPath` without a word.** Read the value first; write only when it is unset or already tlon's; otherwise return `{:error, "…has its own core.hooksPath: <value>"}` so `ensure` refuses rather than disarms a sibling's hooks. Ruled shape:

```elixir
defp point_hooks_at_tlon(repo_path) do
  root = Server.Profiles.main_root()
  hooks = Path.join(root, "scripts/git-hooks")

  if Server.Profiles.main_root(repo_path) == root do
    :ok
  else
    case git(repo_path, ["config", "--get", "core.hooksPath"]) do
      {out, 0} when trim(out) == hooks -> :ok
      {out, 0} -> {:error, "#{repo_path} has its own core.hooksPath (#{String.trim(out)}); not pointing it at tlon's"}
      {_, 1} ->
        case git(repo_path, ["config", "core.hooksPath", hooks]) do
          {_, 0} -> :ok
          {out, _} -> {:error, "could not point hooks at tlon's: #{String.slice(out, 0, 200)}"}
        end
      {out, _} -> {:error, "could not read core.hooksPath: #{String.slice(out, 0, 200)}"}
    end
  end
end
```

(`git config --get` exits 1 when the key is unset; `trim/1` is `String.trim`, written out in the real code.) Change the test: set `elsewhere`, then assert `ensure` returns `{:error, msg}` with `elsewhere` in `msg` and the config still reads `elsewhere`. Keep the idempotency half: a second `ensure` with tlon's value already set is `:ok`.

**2. In the same lines — `Profiles.main_root/1` raises inside `ensure`.** My round-4 follow-up, raised by the grader to blast. Since finding 1 reopens this function, do it now: `main_root/1` returns `{:ok, root} | {:error, out}`; `Smoke.script/0` and `point_hooks_at_tlon/1` match on it; the hooks function passes the error through. Worktree's moduledoc ("never a raise") then holds without exception. Update `profiles_main_root_test.exs` for the tuple.

**3. Test gap — the tlon-own-checkout no-op branch is unpinned.** Add one `worktree_test` case: `ensure` on a linked worktree of `Server.Profiles.main_root()` (or the tmp-repo-plus-linked-worktree shape from `profiles_main_root_test`) leaves `core.hooksPath` unset.

## Not findings
- Scope (grader row 1): the hooks pointing is what makes a sibling seat stamped and fenced (#714); it belongs in this change. No split required.
- Reversibility (grader row 2): real, but finding 1 bounds it to repos that had no hooks of their own; those get tlon's inert-without-TLON_THREAD hooks, which is the intent.
- No `bench_contrast` row among the CHECKS; nothing to call there.