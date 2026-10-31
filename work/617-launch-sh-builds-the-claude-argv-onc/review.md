APPROVE — workline 617, launch.sh hardening.

Verified: `bun test lib/launch.test.ts` → 8 pass, 0 fail (ran in the worktree).

- `remoteControlAtStartup` now goes through `jq -c '. + {…}'` instead of slicing the trailing `}` off a string. jq is already a hard dependency of the sandbox path in the same script (lines 104/106), so no new requirement.
- One `args` array feeds both the dry run and the real `exec`, so the dry run can't drift from what runs. `${args[*]}` for printing and `"${args[@]}"` for exec are the right forms.
- Tests cover the real argv in the dry run (gateway included, no `<…>`) and remote-control off alongside a permissions deny list. The `claude --help` test skips when the binary is absent.

Nit, not blocking: the dry-run `exec:` line is space-joined, so it isn't copy-pasteable when the system prompt has spaces. Fine for a human-readable dry run.