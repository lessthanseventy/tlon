Closes ticket #617: launcher hardening from tzinacan's review of #612.

## What changed

- `adapters/claude-code/launch.sh` builds one argv array (`args=(gateway.sh … claude …)`). The dry run prints that array and the real start runs `exec "${args[@]}"`, so the dry-run line is what would actually run, gateway included. The `<…>` elisions are gone.
- `remoteControlAtStartup: false` is added with `jq` instead of splicing the settings string. It is set for a seat with a permissions deny list too (previously covered only by the splice path). uqbar's study keeps the operator's remote control.
- The fallback `exec claude "$@"` (spawn failed) is unchanged, on purpose.

## How it was checked

- `lib/launch.test.ts`: added three tests (red first). The dry-run exec line is the real argv (`gateway.sh`, no `<…>`); a seat with `TLON_PERMISSIONS_DENY` starts with remote control off; a real-binary guard runs `claude --help` and asserts `--name` (skipped when `claude` is not on PATH).
- `mise run adapters:claude-code:check` → `93 pass, 0 fail`, `tsc --noEmit` clean, exit 0.
