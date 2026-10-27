The push_branch tool takes an optional `branch`, allowed only as `work/<caller's handle>-<name>`, so Uqbar (thread 269, no work branch) can ship a fix as a PR. Review stays required. Closes #460.

- `Publish.own_branch/2` is the authorization; the hooks and the plugin gate are untouched (`work/uqbar-*` already passes the pre-commit).
- Docs: Uqbar's role text and AGENTS.md's push_branch sentence.
- Checked: own prefix allowed; another agent's prefix, `main`, a bare name and a bare prefix refused; the pre-commit passes on `work/uqbar-x` with TLON_THREAD set. The publish, commits and MCP server tests are green.
