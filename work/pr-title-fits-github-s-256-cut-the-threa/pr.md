Cut the PR title to GitHub's 256 in `Workline.Publish` (#739).

`gh pr create` refuses a title over 256 characters, and a sheriff-incident workline's thread title runs past it, so its gated landing never reached GitHub. `Publish.publish/5` now takes the thread title's first line, cut to 256 at most on a word boundary and ending with `…`, as the PR title. When that differs from the full title, the full title heads the PR body, so no reader loses any of it. A title already within 256 is unchanged, with no repeat in the body.

Checked: the Publish suite is red on the new 467-character test (`workline_publish_test.exs:123`, `--title` 467 chars), then green (37 tests, 0 failures). The full `mise run check`-equivalent (`menard run check --in server`) is green: 2435 tests, 0 failed, with one flaky time-based smoke test (`smoke/fixtures_test.exs:132`) that passed on re-run and is unrelated to Publish.
