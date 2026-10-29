# start_smoke is idempotent on the resolved sha, not the ref string

Closes #537.

`Server.Smoke.start/5` resolves the ref to a commit up front (`git rev-parse -q --verify <ref>^{commit}` in the shared git dir, `Server.Profiles.main_root/0`) and stores it in the job args beside the ref.

- Same ref, same sha while a build is up: returns the building job (as before).
- Same ref, moved tip: the old build is stopped through `stop/1` and the new sha is queued; the MCP result says `replaced`.
- Ref that names no commit (unborn, or origin-only and unfetched): refused with `no commit <ref>`; nothing is fetched in the request path.

The script still takes the ref, so the smoke node is unchanged. Tests fake the resolver via `config :server, :smoke_resolve`.

Checked: `menard run test --in server test/server/jobs/smoke_test.exs` (red on the three new cases first, then green) and `menard run check --in server`.
