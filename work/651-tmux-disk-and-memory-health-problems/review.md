APPROVE at ca4b976.

Read the diff (needs.ex, tlon-cli.sh, two test files). Ran `menard run test` on server/test/server/office/needs_test.exs (87 tests, 0 failed) and server/test/server/tlon_cli_test.exs (5 tests, 0 failed).

- retry_job/dismiss_job: both gate on `failed_job/1`, which is `failed_jobs_query()` (discarded or retryable, attempted in the last day, not dismissed). A completed, cancelled, missing or already-dismissed id returns `{:error, :not_failed}`, so nothing runs twice. dismiss_job still dismisses every run that failed the same way.
- tlon-cli job: prints the real result and raises on a refusal. Under `rpc` a raise fails the call, so the exit is non-zero. The quoting is sound: `$jid` and `$verb` expand in the shell, and `#{...}` is Elixir.
- health/0 rescue: a raising vitals read logs a warning and returns `[]`, so the failed-job and other needs still reach the inbox.
- QA (nolan) passed the clean-box path on this sha; it could not seed health rows or job retry/dismiss, so those paths rest on the unit tests, which cover them.

Non-blocking, as follow-ups:
- health first-seen is held in persistent_term, so a restart resets it. A put-away health item returns once, and the 30-minute fail-open clock restarts. The commit names this open and the test pins it.
- vitals/0 persistent_term GC cost: already ticket #659.