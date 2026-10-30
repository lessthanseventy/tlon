APPROVE.

Reviewed `git diff origin/main...HEAD` (I read the diff and grepped; I did not run the suite).

- `OperatorConfig.path/0` now reads the Application env, then `TLON_CONFIG`, then the XDG default. The ordering is right, because the test envs' Application override still wins.
- `release-smoke.sh` starts the scratch node with `TLON_CONFIG="$dir/config.json"`. `$dir` is the `mktemp -d` build dir (line 126), so the smoke node no longer reads or writes the operator's `~/.config/tlon/config.json`.
- Nothing else in `server/lib`, `scripts` or `tasks` hardcodes `config.json`. The path goes through `path/0` everywhere.
- The three path tests cover precedence and restore the env. The script test only checks that the line exists in `release-smoke.sh` (a regex), which is enough for a one-line wiring.

Nit, not blocking: the `@moduledoc` sentence at the top of `operator_config.ex` is now a long line. It could be reflowed in a later commit.