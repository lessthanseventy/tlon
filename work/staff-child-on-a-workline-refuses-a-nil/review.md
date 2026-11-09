APPROVE. Right then: small change, does what the commit says.

Read from the diff (suite not run): staff/2 on a workline with no lead now returns {:error, {:unled, id}}; explain/1 words it with `restaff_now`; the `with` at coordination.ex:107 passes the tuple through.

Non-blocking:
- tool.ex: a stray blank line splits the explain/1 clauses; the new one sits apart from its neighbours.
- The unled test only checks the explain/1 string. The staff/2 nil -> error branch has no test (the PR says no seam reaches it); the off-bench test pins existing behaviour only.
- `restaff_now` is a Server.Workline function, not an MCP tool a manager can call, so the advice may not be actionable. Worth checking what a manager can actually do.

No comment creep; no missing @doc/@spec.