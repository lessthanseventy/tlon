Create each seat's `~/.cache/tlon-scratch/<seat>` dir when the seat is materialised, so its sandbox can bind it.

**Why:** `seat_sandbox/2` grants the seat's scratch root as writable, but nothing created it. bwrap fails on a missing bind source, so a seat (sheriff `scharlach`, `hronir`, `lonnrot`) could never make its scratch worktree. Seven sightings on #655.

**What:** `Profiles.materialise!/2` now `mkdir_p`s the scratch dir (`Path.expand` of `scratch_root/1`) on every spawn, next to the config dir it already creates. The option `:scratch_dir` lets tests point it at a tmp dir and never touch the real `~/.cache`.

**Ticket:** closes #655.

**Checked:**
- RED: `menard run test --in server test/server/profiles_test.exs` failed on the new test (`Expected truthy, got false`), the scratch dir not created.
- GREEN: same command, 73 tests, 0 failures.
