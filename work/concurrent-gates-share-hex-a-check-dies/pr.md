# Each gate boots on a Hex home of its own

Closes ticket #204 (sheriff issue #13): the landing check of #203 died in `Mix.Hex.start` five
seconds in, while `~/.hex/hex.config` and `cache.ets` were rewritten that minute, and the same
branch was green on the full gate.

## What changed

- `scripts/workline-verify.sh` (verify and the landing gate): a `seed_hex_home` step gives the
  throwaway checkout a `HEX_HOME` of its own under it, seeded with the user's `hex.config` (the
  oban-pro repo key, the hex.pm tokens) and `cache.ets` (the registry cache). The 128M of package
  tarballs stay behind: `/tmp` is tmpfs with no reflinks, and the lead's `deps/` is copied anyway.
- `scripts/check-main.sh` and `scripts/release-smoke.sh`: the same three lines, inline.
- `server/test/server/workline_verify_script_test.exs`: `seed_hex_home` lifted out of the script
  and tested — carries config and cache, not tarballs; a machine with no `~/.hex` still gets one.

## Why

Hex reads `hex.config` at every mix boot (`Hex.State` init → `Hex.Config.read`, during dep
loading — the frame in the bounce) and rewrites it in place with a plain `File.write!` whenever a
repo fetch refreshes the hex.pm oauth token (`mix_hex_cli_auth` → `persist_oauth_tokens` →
`Config.update_repos`). The refresh token's `iat` in `~/.hex/hex.config` equals the file's mtime to
the second (2026-10-10 05:33:11Z), so every coworker's `deps.get` can rewrite the file the gates
read. The ask's "retry a check whose tail is a Hex.start crash" is not done: with no shared file
there is nothing to retry.

## How it was checked

- `menard run test --in server test/server/workline_verify_script_test.exs`: red (exit 127,
  `seed_hex_home: command not found`), then green, 8 tests, 0 failures.
- Reproduction, measured on this box (btrfs and tmpfs): a reader looping `File.read!` against a
  writer looping Hex's own `File.write!` of the config sees an **empty** file in 37% of reads
  (7454 of 20108 on btrfs), and a **half-written** one in 0 of ~40k — with same-size and with
  grown rewrites. An empty config boots Hex without its repos; a half-written one (cut at 400
  bytes) fails exactly as #203 did: `Hex.State` raises `TokenMissingError`, then
  `** (MatchError) … {:error, {:hex, …` at `hex.ex:5`. So the crash's shape is reproduced and the
  shared read at every boot is confirmed; the half-written read itself was not caught in the act.
  200 concurrent `mix deps.get` boots against the rewriter: 0 deaths, consistent with that.
- `mise run check` on the branch: see the thread for the run.
