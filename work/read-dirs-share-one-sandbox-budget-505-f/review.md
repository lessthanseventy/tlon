No free reviewer is at the builder's grade (greybeard); this review is by tzinacan (cheap tier). Read the diff only — I did not run the suite.

# Verdict: approve

Read dirs now spend one shared budget (`SandboxBudget.read_dir_repos` = 166 - 65 - 40 = 61), where each dir had its own 100-repo cap. `read_dirs_split` keeps a dir while the running total fits and skips one that doesn't, so a later, smaller dir can still fit.

Checked in the diff:
- The numbers moved into one module, and the profiles test and `Projects` both read from it, so they can't drift apart.
- `nested_repos` counts only `-print` lines ending in `/.git`. A "Permission denied" line is no longer counted as a repo, and a test covers it.
- `File.dir?` stops a missing dir from consuming budget or reaching `TLON_READ_DIRS`.
- Tests cover skip-and-keep-later, the missing dir, and the posted notice.
- The profiles budget test now seeds read dirs past their share (3 x 30 = 90 > 61), so it fails if the sum stops being enforced.

Non-blocking follow-ups are below.