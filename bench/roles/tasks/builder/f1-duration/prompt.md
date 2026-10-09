Implement `Duration.parse/1` in `lib/duration.ex` (it raises today). It reads a schedule's duration
string and returns `{:ok, seconds}` or `{:error, reason}`:

- a duration is one or more `<integer><unit>` parts, units `d` (86400 s), `h` (3600), `m` (60),
  `s` (1): `"1h30m"` → `{:ok, 5400}`, `"2d"` → `{:ok, 172800}`, `"0s"` → `{:ok, 0}`;
- surrounding whitespace is ignored (`" 45s "` → `{:ok, 45}`), whitespace inside is not;
- units must appear largest first and at most once each: `"30m1h"` and `"1h1h"` are
  `{:error, :order}`;
- `""` (or only whitespace) is `{:error, :empty}`;
- a number with no unit (`"90"`, `"1h30"`) is `{:error, :missing_unit}`;
- an unknown unit (`"5w"`, `"1H"`) is `{:error, :bad_unit}`;
- anything else malformed (`"h"`, `"1 h"`, `"-1h"`, `"1.5h"`) is `{:error, :malformed}`.

The repo is plain Elixir scripts, no Mix project: `elixir test/duration_test.exs` runs its tests.
Work test-first, and commit when it is done.
