APPROVE

Right then. Read 39c4f2c in full (4 files, +17/-2). I did not run the tests.

- `:lead_mid_turn` is the atom `staffing.ex:856` returns. Both callers, the operator 409 (`refused/2` catch-all) and `AssignLead`, now go through `Staffing.explain/1`.
- Every other reason falls back to `inspect`, so nothing that printed before changes. The `is_binary` and named `refused/2` clauses still match first.
- The test covers the sentence ("mid-turn", "retry") and the fallback.
- Nit, not blocking: `Staffing.explain` is now the generic fallback for all of OperatorAPI's refusals, not only hand-offs. Harmless today. If other modules grow reason texts, move it to a shared `Refusal` module.