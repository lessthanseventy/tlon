# Review — the-nightly-smoke-goes-red-when-another @ d11bfc9

**Verdict: approve.**

Round two. Read: my review at eab7c7f, then `git diff eab7c7f..d11bfc9` outside `work/…` (072d557, d11bfc9) and the whole branch diff 4234e3c..d11bfc9 once more.

## 1. The blocking finding is fixed as proposed (release_smoke_script_test.exs:251-255)

The witness statement now reads:

    refute out =~ "already being smoked"
    assert out =~ "waiting for"
    refute out =~ "timed out"
    assert File.read!(lock) =~ ~r/\Apid \d+ on http:\/\/127\.0\.0\.1:#{ctx.port}\n\z/

A timed-out run prints `timed out waiting for` and leaves the old holder's record at the path, so it fails both new lines. The test now proves the ticket's deliverable: the second run came out of the wait holding the lock and wrote its own record.

## 2. Follow-up 1 (wording) is fixed

release-smoke.sh:14 and pr.md say "inside a schedule's 30-minute run limit", which matches `@script_timeout_ms` (schedules.ex:27, reset only by `checks queue:`). The 1200 s default stays inside it with room for about one smoke, as read last round.

## 3. The new commit d11bfc9 is a one-line flake fix, not this ticket's scope, and it is right

search_test.exs:197: `assert_receive :locked` → `assert_receive :locked, 5_000`. The holder is a Task taking `ACCESS EXCLUSIVE` on `message` from inside a telemetry handler; under the full gate the 100 ms default is a race, and it was the verify red at 04:20Z. Its own commit, cites #626, suite 18/18 here. Accepted on this branch because it unblocked verify; it is item 1 of #626 and that ticket should note it landed here.

## Spec compliance (unchanged from round one)

Live holder waited on with `flock -w`, finite bound, 0 keeps the old refusal, expiry names the holder, the waited run takes the lock and records its own ran-on, gone-holder reclaim verbatim under `if [ -z "$waited" ]`. The `TLON_SMOKE_LOCK_WAIT` read precedes the `TLON_*` unset.

## Checks
- `menard run test --in server test/server/release_smoke_script_test.exs` → `{"ok":true,"tests":30,"failed":0}` (this session).
- `menard run test --in server test/server/search_test.exs` → `{"ok":true,"tests":18,"failed":0}` (this session).
- CHECKS: `mise run check` exit 0 on the branch at verify, 04:37:45Z, after the red at 04:20Z that d11bfc9 fixes. No `bench_contrast` row: nothing steering edited.
- Trailers: `Co-Authored-By: claude-sonnet-5-5`, `Tlon-Author: emma`, `Tlon-Model` on every builder commit.