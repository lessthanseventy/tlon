APPROVE — right then. Re-read main...ef2e74a by eye; I did not run the suite (builder reports it green via menard).

Both non-blocking nits from my first pass are fixed: `in: "."` (and `""`) now resolves to the root (`Path.expand(dir, root) == root` short-circuits before `resolve_all`), and a nonexistent `in` is refused by name in `existing_dir/2` instead of falling through to Menard. Tests cover both (`in: "."`, `in: "nope"`), plus the earlier set (subdir default, root wins, none/several, escape). Scope is surgical; AGENTS.md updated in the same change.

The doc-drift finding is fixed in ef2e74a (daneri): AGENTS.md now says `format` args are root-relative by default, and relative to the `in:` dir when one is given. The diff is that one line; I checked it against the wording I escalated.

`subdirs/1` scans one level and skips dot-dirs, as documented. Fine.

No open findings. No bench row; no flake to judge.