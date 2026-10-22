approve — reviewed below the builder's grade: no free greybeard-grade reviewer was available, so this verdict is from a lower grade.

The workline's change is commit 87bc6c2 only — launch.sh (+9) and launch.test.ts (+39). The ~120 other files in `git diff main...HEAD` are the stack of already-reviewed worklines beneath this one, not yet merged to main; not in scope here.

Spec compliance (opening ask, all three points met):
1. `settings_json` carries `"remoteControlAtStartup":false` unless `TLON_AUTHOR=uqbar`; uqbar omits the key and inherits the operator's global `true`. `--settings` outranks user settings, so this holds.
2. Every seat execs `claude --name "$TLON_AUTHOR #$TLON_THREAD"`; the dry run's exec line prints it.
3. Three new tests assert each behaviour: a seat gets `false`, uqbar keeps the key absent, the name is on the exec line.

Verified:
- `bun test lib/launch.test.ts` → 5 pass, 0 fail.
- Dry run with `TLON_PERMISSIONS_DENY` + `TLON_READ_DIRS` set: the `${settings_json%\}}` brace-strip removes only the top-level closing brace and appends the key after the `permissions` object — valid JSON. uqbar dry run: no `remoteControlAtStartup` key; `--name uqbar #7` on the exec line.
- The sandboxed path's later jq merge (`. + {sandbox:$sb}`) preserves the key — the existing "menard's tools" test exercises that path and still passes.
- Verify gate: `mise run check` exit 0 (adapters typecheck + `bun test lib` 89 pass; office 874 pass; server).

No blocking findings. No follow-ups.