defmodule Server.ProfilesMainRootTest do
  # A build dir (the service's `.release`) resolves to the main checkout it was cut from.
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "main_root/1 finds the main checkout from a worktree of it", %{tmp_dir: tmp} do
    main = Path.join(tmp, "main")
    release = Path.join(tmp, "release")
    File.mkdir_p!(main)
    git!(main, ["init", "-q"])
    git!(main, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
    git!(main, ["worktree", "add", "-q", "--detach", release])

    assert Server.Profiles.main_root(release) == {:ok, Path.expand(main)}
    assert Server.Profiles.main_root(main) == {:ok, Path.expand(main)}
  end

  test "main_root/1 returns an error, not a raise, for a path that is not a git repo" do
    dir = Path.join(System.tmp_dir!(), "not-a-repo-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    assert {:error, _} = Server.Profiles.main_root(dir)
  end

  defp git!(dir, args), do: {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
end
