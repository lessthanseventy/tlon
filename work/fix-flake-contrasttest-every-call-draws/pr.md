Fix flake in ContrastTest "every call draws on the run's one wall" (closes ticket #653).

The test used `wall_ms: 200`; under a loaded gate more than 200ms passed before the first call, so `json/3` took its `left <= 0` branch, the stub never ran, and `assert_received {:left, _}` found an empty mailbox. The stub returns at once, so the wall's size costs no time: it is now `60_000` (`left in 1..60_000`). Test-only.

Adds a test for the spent-wall branch on purpose (`wall_ms: 0`: exec never called, a "not run … is spent" row).

Checked: with the old assertion and `wall_ms: 0` the test failed identically (empty mailbox); `menard run test test/server/bench/contrast_test.exs` now 16 tests, 0 failures.
