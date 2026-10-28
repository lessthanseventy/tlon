APPROVE — right then. Re-read the diff main...09aa943 by eye; I did not run the suite (builder reports it green via menard).

Both non-blocking nits from my first pass are fixed: `in: "."` (and `""`) now resolves to the root (`Path.expand(dir, root) == root` short-circuits before `resolve_all`), and a nonexistent `in` is refused by name in `existing_dir/2` instead of falling through to Menard. Tests cover both (`in: "."`, `in: "nope"`), plus the earlier set (subdir default, root wins, none/several, escape). Scope is surgical; AGENTS.md updated in the same change.

Non-blocking:
- AGENTS.md says "`format` args stay root-relative"; that holds only for the default. With an explicit `in: "server"`, `format` runs there and its args are relative to that dir. One clause of doc drift.
- `subdirs/1` scans one level and skips dot-dirs, as documented. Fine.

No bench row; no flake to judge.