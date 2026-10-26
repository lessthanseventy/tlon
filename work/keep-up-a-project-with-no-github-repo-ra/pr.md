keep_up: skip repos with no GitHub remote; one rollout note per unreadable repo

Closes #613. keep_up filed a rollout item per `gh` read per pass for a repo with no origin or one GitHub can't resolve.

- A repo whose origin is missing or not on github.com has no `gh` reads and no rollout item, said once in the log. Its main is still followed and drift still surfaces.
- GitHub origins match in https (with userinfo), ssh, `ssh.github.com:443` and `git://` forms.
- A repo whose reads fail keeps one keyed note, cleared only when both reads of a pass succeed.

Checked: `menard run test` keep_up_test 22/22 (new tests red first); `menard run check --in server` 2076 tests, 0 failed.
