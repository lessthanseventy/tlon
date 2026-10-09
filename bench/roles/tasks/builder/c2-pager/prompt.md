Bug report from the operator: "the thread list skips the first ten messages, and the last few never
show up at all — with 25 messages I only ever see two pages."

The pagination is `lib/pager.ex` (pages are numbered from 1). Find the bugs, fix them test-first, and
commit. The repo is plain Elixir scripts, no Mix project: `elixir test/pager_test.exs` runs its tests.
