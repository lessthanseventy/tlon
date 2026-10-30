Search.history: details/2 and with_window/2 carry the query timeout

`history/3` documents `timeout:` as bounding each query, but the details read and the per-hit
window reads (`around: n`) called `Repo.query!` without it, so they fell back to the repo default.
`do_history` now computes `timeout(opts)` once and passes it to `details/3`, `with_window/3` and `count`.

Closes #559.

Checked: two new search_test cases hold the message table's lock the moment the preceding query
returns, so only the details (resp. window) query can time out; both go red on main (the search
answers instead of `{:error, :timeout}`) and green with the change. `menard run check --in server`
runs the full server gate.
