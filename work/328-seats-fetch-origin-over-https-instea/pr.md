Seats fetch origin over HTTPS, pushes stay on SSH (closes #328).

A sandboxed seat's plain `git fetch origin` died on `~/.ssh/known_hosts: Permission denied`. The repo is public, so
`server:setup` now sets `url."https://github.com/".insteadOf git@github.com:` and
`url."git@github.com:".pushInsteadOf git@github.com:` in the shared `.git/config`; `server:doctor` gains a
`git fetch:` line naming whichever is missing (`Server.Doctor.git_fetch_urls/1`). AGENTS.md's sandbox section
gets the bullet. The fetch helper and the sandbox profile are untouched.

Checked: `Server.DoctorTest` red first (undefined `git_fetch_urls/1`), then 13 tests green; `mix format --check-formatted` clean;
on a scratch repo with the two lines, `remote get-url origin` reads https and `--push` reads git@.
Not run: `server:setup` itself and a real `git fetch origin` from a seat (a seat must not write the shared config; the
operator runs `mise run server:setup` once).
