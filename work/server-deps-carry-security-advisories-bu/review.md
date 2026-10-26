# Review: server-deps-carry-security-advisories-bu @ 2128e82

**Verdict: approve.** Lock-only bump, exactly what the ticket asked for, checksums match hex.pm, gate green twice. One honesty defect in pr.md (follow-up), and the release smoke the ticket asked for has not run yet; it gates the cut, not the merge, so it does not block here.

## Findings

1. **The diff is what it says it is.** `server/mix.lock` only: bandit 1.12.5→1.14.0, plug_crypto 2.2.0→2.2.1, thousand_island 1.5.0→1.6.0. `server/mix.exs` untouched (`{:bandit, "~> 1.0"}`, `{:plug, "~> 1.0"}` still satisfied). Plus the new `pr.md`.

2. **Lock entries verified against hex.pm, not eyeballed.** Outer checksums match the registry for all three:
   - bandit 1.14.0 `2d07630e…a48746` ✓, requirements `hpax ~> 1.1`, `thousand_island ~> 1.6`, `plug ~> 1.18` — the lock's hpax 1.1.0, thousand_island 1.6.0, plug 1.20.3 satisfy them.
   - plug_crypto 2.2.1 `4417ccbd…b94b6` ✓
   - thousand_island 1.6.0 `4d472047…057a3` ✓

3. **Advisories cleared** per the builder's run (emma, #14497): `deps.get` prints no VULNERABLE line, `hex.audit` says "No retired or security advisory packages found". I could not rerun deps.get from this sandbox; attributed, not re-verified.

4. **Gate.** CHECKS: `mise run server:check` passed on 2128e82 (run_task, 23:37); verify's full `mise run check` passed at 23:55 (server + office 913/0). Both on this head.

5. **Behaviour changes riding in with bandit 1.13/1.14** (changelog): HTTP/1 Host/authority validation enforced, request line must be exactly three words with `HTTP/1.1`/`1.0`, HTTP/2 stream and header-list limits now default-on, stricter chunked-body grammar. Our clients are the office TUI, the adapters and tlon-cli hitting `127.0.0.1:<port>` with ordinary Host headers, and the web UI is a loopback Phoenix endpoint on `Bandit.PhoenixAdapter`. Low risk, but it is exactly what the ticket's release smoke is for.

6. **Release smoke not run.** Ticket #624 and Uqbar (#14481) asked for `server:check` plus a release smoke because bandit is a minor bump. Emma could not run it (sandbox refuses; `run_task` does not offer it) and said so (#14507). Not blocking the merge: a cut requires `release:smoke` to have passed on exactly the candidate commit (`Server.Release.Candidate`), so the smoke happens before this ever runs live. Whoever cuts the next release should watch that row.

7. **pr.md misstates verification** (follow-up). Its last line claims "server:check and release:smoke run via run_task on this head". The smoke did not run and run_task cannot run it; the builder's own thread message says as much. The PR description must not claim a check that did not happen.

No `bench_contrast` row in CHECKS, so nothing to say on canaries.
