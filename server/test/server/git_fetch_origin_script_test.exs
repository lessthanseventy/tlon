defmodule Server.GitFetchOriginScriptTest do
  # scripts/git-fetch-origin.sh: a fetch that loses a ref's lock to another fetch in the shared .git is
  # retried; any other failure is not. git is stubbed, so the race is exact.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/git-fetch-origin.sh", __DIR__)

  @stub ~S"""
  #!/bin/sh
  [ "$3" = remote ] && { echo https://example.invalid/r.git; exit 0; }
  n=$(($(cat "$CALLS" 2>/dev/null || echo 0) + 1)); echo "$n" >"$CALLS"
  [ "$n" -gt "$FAILS" ] && exit 0
  echo "$SAYS" >&2
  exit 1
  """

  @lost "error: cannot lock ref 'refs/remotes/origin/main': is at aaa but expected bbb"

  setup do
    tmp = Path.join(System.tmp_dir!(), "git-fetch-origin-#{System.pid()}-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "git"), @stub)
    File.chmod!(Path.join(tmp, "git"), 0o755)
    %{tmp: tmp}
  end

  defp fetch(tmp, fails, says) do
    calls = Path.join(tmp, "calls")

    env = [
      {"PATH", tmp <> ":" <> System.get_env("PATH")},
      {"CALLS", calls},
      {"FAILS", to_string(fails)},
      {"SAYS", says}
    ]

    {out, code} = System.cmd("bash", [@script, tmp, "main"], env: env, stderr_to_stdout: true)
    {code, out, calls |> File.read!() |> String.trim() |> String.to_integer()}
  end

  test "a fetch that lost the lock is retried until the winner is done", %{tmp: tmp} do
    assert {0, "", 3} = fetch(tmp, 2, @lost)
  end

  test "a lock that stays lost is a failure, and says so", %{tmp: tmp} do
    assert {1, out, 4} = fetch(tmp, 99, @lost)
    assert out =~ "cannot lock ref"
  end

  test "any other failure is not retried", %{tmp: tmp} do
    assert {1, out, 1} = fetch(tmp, 99, "fatal: could not resolve host")
    assert out =~ "could not resolve host"
  end
end
