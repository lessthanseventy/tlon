APPROVE.

Right then. The one-line filter in `restaff/1`'s intent clause (staffing.ex:45) reuses `leading_another?/2`, the same rule the other stage restaffs use (lines 76, 117, 230). If the whole bench is busy, `Coworker.lead([])` returns nil and the thread is left unchanged, which is the stated behaviour.

Checked by reading the diff only. I did not run the suite. The commit message and pr.md say the new tests went red first and are green now, and I have not confirmed that.

- **Tests:** two cases cover the named busy lead (asserts `hronir` leads and a "→ hronir leads, not tertius" message) and the default-lead case (no "leads, not" message). Both follow the existing `bench_ws`/`open!` pattern.
- **Standards:** no comment creep, no ticket keys in code, and no new public function.
- **Nit, not blocking:** the comment above `restaff` still says intent is led by "the bench's lead (its first builder)", with no mention of the free-seat filter.