defmodule Server.SmokeScriptTest do
  # The held smoke runs main's copy of release-smoke.sh, even when the service asks from a build dir.
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "main_root/1 finds the main checkout from a worktree of it", %{tmp_dir: tmp} do
    main = Path.join(tmp, "main")
    release = Path.join(tmp, "release")
    File.mkdir_p!(main)
    git!(main, ["init", "-q"])
    git!(main, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
    git!(main, ["worktree", "add", "-q", "--detach", release])

    assert Server.Smoke.main_root(release) == Path.expand(main)
    assert Server.Smoke.main_root(main) == Path.expand(main)
  end

  defp git!(dir, args), do: {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
end
