release:smoke: reclaim a per-commit lock whose holder is gone (closes #389)

A hold smoke refused with "already being smoked (pid N on URL)" for a holder nobody could see.
The per-commit flock is the only liveness signal, and a lock can outlive its run (a daemon the node
started inherited fd 8) or belong to another sandbox's pid namespace. Now:

- on a lost flock the holder is real only if its pid lives, its url answers /api/office, or its record
  is under 20 minutes old; otherwise the lock file is replaced and taken, saying so;
- the record is truncated when written, so a shorter one leaves no tail of the last run's;
- the scratch node no longer inherits the commit lock (fd 8), so it lives and dies with the run.

Tests (release_smoke_script_test): a gone holder is reclaimed; an old record whose url answers is still
refused; the existing live-holder refusal stays green.
