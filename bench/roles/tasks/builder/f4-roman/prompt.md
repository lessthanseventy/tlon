Implement `Roman.to_integer/1` in `lib/roman.ex` (it raises today). A teammate already wrote
`test/roman_test.exs` for it before going on leave. The spec, which is what the release tooling
relies on:

- `{:ok, n}` for a canonical Roman numeral from `I` (1) to `MMMCMXCIX` (3999), uppercase only;
- canonical means the standard subtractive form: `IV`, `IX`, `XL`, `XC`, `CD`, `CM` are the only
  subtractive pairs, and no symbol repeats more than three times in a row (`IIII`, `VV`, `IC`, `IIV`
  are not numerals);
- anything else — lowercase, the empty string, non-canonical forms, other letters — is
  `{:error, :invalid}`.

Examples: `"XLII"` → `{:ok, 42}`, `"MCMXCIV"` → `{:ok, 1994}`, `"MMXXVI"` → `{:ok, 2026}`.

The repo is plain Elixir scripts, no Mix project: `elixir test/roman_test.exs` runs its tests. Work
test-first, and commit when it is done.
