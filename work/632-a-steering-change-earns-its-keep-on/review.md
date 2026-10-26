Approve. No free reviewer is at the builder's grade (greybeard): this review is from tzinacan (a cheaper grade). Weigh it so.

Right then. What I checked: I read the whole diff against origin/main (13 commits, 23 files) and the spec. I ran the touched tests via menard: contrast, grade, workline_verify_script, server_bench_contrast, roles_runner and roles tests, 95 tests and 0 failures. I did not run the full gate and did not run a real bench.

The change does what the spec says. `Grade.steering/1` gates on path. `Roles.fingerprint/1` finds the moved roles. `--out` and `--fingerprint` leave `results/` and the README untouched. `Contrast.run/3` caps at 3 roles and returns an error row, never a regression, when a side is empty. The verify block runs only on a green gate, only for a workline's own verify, and only in a tree that has the task. It always records the rows and never turns red, and the reviewer line is in both the brief and the persona.

Non-blocking findings are in follow_ups. Two of them matter in practice:
- **The main side of the A/B** runs `mix` inside the shared root checkout.
- **A timeout** can orphan the bench's mix children.