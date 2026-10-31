APPROVE — #623, branch work/623-the-role-bench-says-when-a-role-has (head d2aff4e).

Right then: read the diff against main; I did not run the suite myself.

- Runner: roles with no tasks in the suite are filtered out of `run/3` (`tasks != []`), so no 0/0 record is written. The mix task names the skipped roles via `roles -- records`.
- `--role X` with no tasks in the suite now fails via `require_tasks/3` (exit 1, nothing run). `Keyword.has_key?(opts, :role)` is the right discriminator.
- Promoting s3-epic-parent-law to canary matches pr.md's reasoning (fastest passing senior task). A fixture test pins it as the one senior canary task.
- Tests cover both paths. Moduledoc updated in the same change; grep found no other stale docs.
- The gate's one red (harness_test.exs:212) is main's #754 per pr.md; I did not verify it. It blocks landing, not this review.

Nits (not blocking): `run/3` and `require_tasks/3` repeat the `Roles.roles()[role].set` + `Roles.load` lookup; the skip line says "tier" while the error says "tasks".