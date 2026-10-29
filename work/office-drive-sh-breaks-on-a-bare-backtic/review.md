Verdict: APPROVE — ac17508 on work/office-drive-sh-breaks-on-a-bare-backtic (2 commits over 32f5443).

The witness statement, scripts/office-drive.sh:

    *) if [ "${#step}" -eq 1 ]; then t send-keys -t 0 -l -- "$step"; else eval "t send-keys -t 0 $step"; fi

A one-character step bypasses the eval; everything longer keeps it. That is exactly hronir's steer (#17157): the smoke's `"'$title'"` and the walks' `'108'` are untouched.

What I verified myself, not took on faith:

1. Red/green of the unit test. I copied scripts/office-drive.test.sh beside main's copy of office-drive.sh in a scratch dir and ran both.
   base (origin/main):   FAIL ` FAIL " FAIL ; FAIL &   ok 'my title' ok '108' ok Enter   rc=1
   branch (ac17508):     7/7 ok                                                          rc=0
   The four failures are all "sent []": the eval swallowed the key, which is #535's symptom.

2. Real tmux accepts the new form. `tmux send-keys -t 0 -l -- '`'` then `'"'` into a fresh pane running cat; capture-pane shows `` `" ``. So `-l --` is not a stub-only success. The builder's own replay (CHECKS: run.sh cast red at a602e85~1 with "eval: line 61: unexpected EOF", green at ac17508 with "THE CAST · people · name") agrees.

3. Nothing existing regresses. I grepped every one-character step in the walks and the smoke: letters, digits, `/`, `.`, `_`, `c`, `R`. For a printable character `send-keys -l X` and `send-keys X` are the same keystroke; tmux has no one-character key names. The verify gate (mise run check, exit 0 in CHECKS) ran the new test inside check:names.

4. The fix reaches the reporter. Server.Smoke.drive passes `keys` straight as argv to office-drive.sh (server/lib/server/smoke.ex), so drive_smoke(keys: ["`"]) hits the new branch once a held smoke carries this commit.

5. Scope. The ticket proposed "quote keys in the eval"; the tech lead redirected to the one-character literal, and the branch does that and no more. A longer step containing a backtick (a title with one) still dies in the eval; the usage comment says so, and that is not this ticket.

No bench_contrast row in CHECKS. pr.md names the ticket, the change and the checks accurately.

Two non-blocking follow-ups are listed below.