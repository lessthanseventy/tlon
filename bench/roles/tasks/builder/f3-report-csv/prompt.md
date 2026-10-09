`lib/report.ex` renders the nightly check report as a text table. Two things, in this order:

1. Its three line builders (`header/0`, `row/1`, `total/1`) each repeat the same column padding. Fold
   the column layout into one place so a column's width is said once. The text output must not change
   by a single byte — `test/report_test.exs` pins it.
2. Then add CSV: `Report.render(rows, :csv)` returns `check,runs,pass` and one line per row, each line
   ending in `\n`, with no total line. The ratio has two decimals as in the table (`0.86`). A name
   holding a comma or a double quote is wrapped in double quotes, with any double quote inside doubled
   (`say "hi", ok` → `"say ""hi"", ok"`). `Report.render(rows)` stays the text table.

The repo is plain Elixir scripts, no Mix project: `elixir test/report_test.exs` runs its tests.
Work test-first, and commit each step.
