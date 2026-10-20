# Plan — bound a seat sandbox's bwrap arguments (#455)

## Problem
`Server.Profiles` `@tlon_sandbox` `allowWrite` lists the ficciones repo, tlon's checkout (with its
`.worktrees/*`), `/tmp`, and 22 `~/.cache/<name>` dirs (`@dev_caches`). Claude Code adds bwrap mounts for
every protected git file of every repo found under a write root. Three of those caches grow without
bound: `mix` (116 repos), `tlon-scratch` (67), `menard-scratch` (28). Today: ~260 repos -> 11059 args
(~42.5 args/repo, derived: 11059/260; not measured per repo) against bwrap's limit of 9000.

## Budget (the number)
**7500 bwrap args per seat** (9000 minus ~17% headroom), modelled at **45 args/repo**:

| reserve | repos | args |
|---|---|---|
| ficciones + tlon checkout + its worktrees (fixed paths) | 65 (49 today) | 2925 |
| tool caches, `~/.cache/<name>` | 2 each x 20 = 40 | 1800 |
| this seat's own scratch dir | 40 | 1800 |
| total | 145 | 6525 (<= 7500) |

The fix is structural, not a prune: no write root may be a dir that accumulates repos across seats.
- `mix`, `tlon-scratch`, `menard-scratch` leave `@dev_caches`.
- Each seat gets exactly one scratch root, `~/.cache/tlon-scratch/<seat name>`, so a seat's count is
  its own repos, not the box's history.

Not in scope: deleting existing scratch dirs (operator's call), a runtime repo counter (YAGNI).

## Task 1 — RED: test that holds the budget
File: `server/test/server/profiles_test.exs`. Replace the test "its write roots are narrow enough for
bwrap" (it asserts `~/.cache/mix` and `tlon-scratch` ARE writable; that is the bug). Add:

```elixir
    # bwrap takes 9000 args; Claude Code mounts ~45 per repo found under a write root
    @bwrap_budget 7500
    @args_per_repo 45
    @fixed_repos 65

    @tag :tmp_dir
    test "a seat's write roots stay under the bwrap budget however many repos the box has", %{tmp_dir: home} do
      for seat <- ["hronir", "zunz"], archetype <- [:builder, :qa] do
        roots =
          Profiles.instantiate(%{archetype: archetype, name: seat}).sandbox["filesystem"]["allowWrite"]

        # unbounded growers: 300 repos in each cache a seat might share, and in every other seat's scratch
        for cache <- ~w(mix menard-scratch tlon-scratch/other-seat), do: seed_repos(home, ".cache/#{cache}", 300)
        # tool caches hold a couple of repos; the seat's own scratch is allowed 40
        for cache <- Profiles.dev_caches() -- ~w(mix menard-scratch tlon-scratch), do: seed_repos(home, ".cache/#{cache}", 2)
        seed_repos(home, ".cache/tlon-scratch/#{seat}", 40)

        count =
          roots
          |> Enum.filter(&String.starts_with?(&1, "~/"))
          |> Enum.map(&Path.join(home, String.replace_prefix(&1, "~/", "")))
          |> Enum.map(&length(Path.wildcard(Path.join(&1, "**/.git"), match_dot: true)))
          |> Enum.sum()

        assert (count + @fixed_repos) * @args_per_repo <= @bwrap_budget,
               "#{seat}/#{archetype}: #{count} repos under ~ write roots"
      end
    end

    test "no seat can write another seat's scratch dir, nor the shared growers" do
      writes = Profiles.instantiate(%{archetype: :builder, name: "zunz"}).sandbox["filesystem"]["allowWrite"]
      assert "~/.cache/tlon-scratch/zunz" in writes
      for gone <- ~w(~/.cache/mix ~/.cache/tlon-scratch ~/.cache/menard-scratch ~/.cache ~/.local),
          do: refute(gone in writes)
    end

    defp seed_repos(home, rel, n) do
      for i <- 1..n, do: File.mkdir_p!(Path.join([home, rel, "r#{i}", ".git"]))
    end
```
(put the `@`-attrs and `defp` at module level if the formatter/credo wants them there.)

Verify RED: `~/projects/menard/bin/menard run test --in server server/test/server/profiles_test.exs`
-> both new tests fail (count ~ 300x3 repos; `tlon-scratch/zunz` absent).
Commit: `test: a seat's write roots stay under the bwrap budget`.

## Task 2 — GREEN: per-seat scratch root, growers out
File: `server/lib/server/profiles.ex` (only these three edits).
1. `@dev_caches`: delete `mix`, `menard-scratch`, `tlon-scratch`.
2. Add (beside `dev_caches/0`):
```elixir
  @doc "A seat's one scratch root: its worktrees live here, so its bwrap mounts are its own."
  def scratch_root(name), do: "~/.cache/tlon-scratch/" <> name

  defp seat_sandbox(nil, _name), do: nil

  defp seat_sandbox(sandbox, name),
    do: update_in(sandbox, ["filesystem", "allowWrite"], &(&1 ++ [scratch_root(name)]))
```
3. In `instantiate/2`: `sandbox: seat_sandbox(t.sandbox, name),`.
Update the comment above `@dev_caches`/`"allowWrite"` to say why those three are absent (a write root
that accumulates repos across seats takes bwrap past 9000).
Verify GREEN: same command as Task 1, plus `menard run test --in server server/test/server/profiles_test.exs`
whole file (the fingerprint and materialise tests must stay green).
Commit: `profiles: seats write their own scratch dir, not the shared growers`.

## Task 3 — point the scratch tooling at the seat dir
Without this, `mise run scratch:new` makes worktrees where the seat can no longer write.
1. Read `scripts/scratch-new.sh` / `scratch-prune.sh` (via `mise tasks | grep scratch`; `tasks/*.toml`).
2. RED: extend its existing script test (find it under `server/test/` with `menard find calls` / `ls
   server/test | grep scratch`): with `TLON_HANDLE`-style seat env set to `zunz`, the worktree path is
   `$HOME/.cache/tlon-scratch/zunz/<name>`; with it unset (operator) the path is unchanged
   (`~/.cache/tlon-scratch/<name>`). Find the real seat env var name first: `env | grep ^TLON_` in a
   seat pane; use that, do not invent one.
3. GREEN: the script builds `base=~/.cache/tlon-scratch${SEAT:+/$SEAT}`; `scratch:prune` walks both the
   flat dir and `*/` one level down.
4. Update the AGENTS.md line "a detached worktree under `~/.cache/tlon-scratch/`" to say per-seat.
Verify: that script test green. Commit: `scratch: worktrees go under the seat's own dir`.

## Task 4 — mix must still work with `~/.cache/mix` read-only
A seat's `mix` may write `~/.cache/mix` (hex/rebar archives). With `~/.cache` in `allowRead` only, that
write now fails.
1. Check what writes there: from a seat pane run `menard run test --in server` and watch for EACCES; or
   `strace`-free: `find ~/.cache/mix -newer <start-marker> -maxdepth 2`.
2. If nothing is written at test time: done, record it. If something is: point it at the seat scratch
   (`MIX_XDG`/`MIX_HOME` in `Server.Harness.ClaudeCode` launch env -> `<scratch_root>/mix`) with its own
   test beside the existing launch-env tests. Do NOT re-add `~/.cache/mix` (116 repos).
Commit with the finding in the message.

## Task 5 — gate and ship
- `~/projects/menard/bin/menard run check --in server` -> `ok:true`.
- Shipping (builder cannot do this; operator or uqbar): after merge, `release:cut`. The profile's
  fingerprint changes so idle panes roll themselves between turns; a seat already refused by the limit
  (zunz, #298) cannot run a turn that finishes cleanly, so expect it to need `server:stop` + restart.
  #298 unblocks only after that fresh launch.
- Real-number proof, in a fresh seat after the restart: `git branch --show-current` runs in Bash (it
  currently errors "N bwrap arguments ... at most 9000"). Record the check with `record_check`.

## Definition of done
Profile tests green; `menard run check --in server` green; a freshly launched seat runs Bash; the
budget (7500 args, 45/repo, reserves above) stated in the test comment. Open: the 45 args/repo figure is
derived from the aggregate, not measured per repo — if a fresh seat still reports > 7500 args in the
refusal message, recalibrate `@args_per_repo`.
