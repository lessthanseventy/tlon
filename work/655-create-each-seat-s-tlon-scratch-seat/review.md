APPROVE.

Right then: the fix is the smallest that works. `materialise!/2` now `mkdir_p!`s `Path.expand(scratch_root(name))`, the same path `seat_sandbox/2` grants as writable. Both real callers (`Arbiter.Tmux`, `Crew.Tmux`) materialise before launch, so the bwrap bind source exists. `mkdir_p!` is idempotent. The new test goes red without the change (per the PR note), and the existing materialise tests now use a tmp `:scratch_dir`, so they don't touch the real ~/.cache.

Checked by reading the diff and grepping callers. I did not run the suite.

Minor: tests that reach `materialise!` through `Arbiter.Tmux` or `Crew.Tmux` without `:scratch_dir` will leave empty dirs under the real ~/.cache/tlon-scratch. Cosmetic.