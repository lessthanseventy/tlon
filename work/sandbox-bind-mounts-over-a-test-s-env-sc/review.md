APPROVE. No free reviewer is at the builder's grade (greybeard); reviewed by runeberg alone.

Diff: 2 commits, one test file plus pr.md.
- The gate stub's env dump moves from `gate.log.env` to `gate.log.vars`. The reader of that file (the #620 assertion) is updated in the same change.
- New test: `the gate leaves no *.env file behind`. It wildcards `**/*.env` with `match_dot: true` under the test's tmp.
- The fix is the right one. The seat sandbox bind-mounts /dev/null over `*.env`, so the file name was the problem. Tolerating busy mounts in the cleanup would not help, as pr.md argues.

Verified: I ran `menard run test --in server test/server/workline_verify_script_test.exs` and got `{"ok":true,"tests":32,"failed":0}`.
Not verified: the sandboxed full gate, and that the new test goes red before the rename. I take both from pr.md.

I grepped server/test for other `.env` names and found no other fixture that writes one.