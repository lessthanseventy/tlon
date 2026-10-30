# PR reviews open as plain threads, not build worklines

`Tickets.start_thread/2` always promoted to a workline at build, so a ticket asking for a PR review owed commits the reviewer can't write: 3 nags, a leaf roll, then a stuck alarm. A ticket labelled `review` (`Tickets.review?/1`) now opens a plain thread (stage nil, nothing owed) and its ask states the owed `review_branch` verdict. Other tickets are unchanged.

Closes #737 (dup #729). Out of scope: auto-close on merge (#695).

Checked: new test in `tickets_test.exs` red then green; `menard run check --in server` ok, 2434 tests, 0 failed.
