# Point the coworker-profile materialiser (Server.Profiles.base_dir_root/0) at a throwaway dir so no
# test writes into the real `~/.pi/profiles` — both a hygiene fix (Crew.spawn materialises a profile
# as a side effect) and what lets the suite run under a sandbox with a read-only home. Set ONCE here,
# before any test resolves the root, and never mutated afterwards, so `async: true` tests don't race
# on it (a test that needs its own root still passes `base:`/`root:` opts or overrides+restores).
if !System.get_env("PI_CODING_AGENT_DIR") do
  pi_root = Path.join(System.tmp_dir!(), "console-test-pi-#{System.pid()}")
  System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))
end

ExUnit.start()
