# Stop sharing server/deps across worktrees

A `mix deps.update` on one branch rewrote `server/deps` for every checkout, because each worktree
linked its `deps` to the main checkout's. #250's check failed "lock mismatch: decimal out of date"
after a decimal bump fetched into the shared dir (issue #30).

- `Server.Worktree` no longer links `server/deps` to the main checkout; a fresh worktree seeds its
  own copy where the lockfile matches (`399c364`, `f5a42ce`, already on main). Only the desktop
  shell's `node_modules`, which links into the read-only nix store, is still shared.
- `scripts/workline-verify.sh`: the lead's deps are copied by `copy_deps`, which dereferences with
  `cp -rL`. A worktree made before that fix still has `server/deps` as a symlink into the shared
  dir, and a plain `cp -r` copied the link, so the gate's `mix deps.get` wrote through it.

Not in this change: `node_modules` has the same hazard against `bun.lock` for a checkout that
shares it by symlink. It is out of scope here; the shell's store-backed link is read-only, so it
is not written through today.

Ticket #451. Closes issue #30.

Checked:
- `server/test/server/workline_verify_script_test.exs`: new test "a deps dir that is a symlink into
  a shared one is copied, never linked". Red first (`copy_deps` undefined, then the symlink still
  copied with `cp -r`), green with `cp -rL`. The file: 18 tests, 0 failures.
- `server/test/server/worktree_test.exs`: the seeding and link tests from `f5a42ce`.
- `bash -n scripts/workline-verify.sh`, `menard run check --in server`: see the commit.
