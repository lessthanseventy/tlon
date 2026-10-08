defmodule Server.ReleaseScriptTest do
  # scripts/release.sh, the release pointer: only merged work ships, only forward unless rolled back,
  # and a cut leaves .release checked out at the release. Real git; mix, curl and the restart stubbed.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/release.sh", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "release-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    repo = Path.join(dir, "tlon")
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)

    for {name, body} <- [{"mix", "exit 0"}, {"curl", ~s(echo '{"restarting":true}')}] do
      File.write!(Path.join(bin, name), "#!/bin/sh\n#{body}\n")
      File.chmod!(Path.join(bin, name), 0o755)
    end

    sh!(dir, "git init -q --bare origin.git && git clone -q origin.git tlon")
    File.mkdir_p!(Path.join(repo, "scripts"))
    File.cp!(@script, Path.join(repo, "scripts/release.sh"))
    File.mkdir_p!(Path.join(repo, "server"))
    File.write!(Path.join(repo, "server/mix.exs"), "")

    sh!(repo, """
    git config user.email t@t && git config user.name t &&
    git add -A && git commit -qm one && git branch -M main && git push -q origin main &&
    git commit -q --allow-empty -m two && git push -q origin main &&
    git checkout -qb side && git commit -q --allow-empty -m unmerged && git checkout -q main &&
    git branch release/pointer
    """)

    %{repo: repo, bin: bin}
  end

  defp sh!(cwd, cmd) do
    {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
    out
  end

  defp release(%{repo: repo, bin: bin}, args) do
    env = [{"PATH", "#{bin}:#{System.get_env("PATH")}"}, {"TLON_RELEASE_DIR", Path.join(repo, ".release")}]
    System.cmd("bash", [Path.join(repo, "scripts/release.sh") | args], cd: repo, env: env, stderr_to_stdout: true)
  end

  defp rev(repo, ref), do: repo |> sh!("git rev-parse #{ref}") |> String.trim()

  test "a cut to a commit not on origin/main is refused", ctx do
    assert {out, 1} = release(ctx, ["cut", rev(ctx.repo, "side")])
    assert out =~ "not on origin/main"
    assert {_, 1} = System.cmd("git", ["-C", ctx.repo, "rev-parse", "-q", "--verify", "refs/heads/live"])
  end

  test "a cut moves release forward, checks .release out at it, and asks for a restart", ctx do
    assert {out, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    assert out =~ "restart:"
    assert {_, 0} = release(ctx, ["cut"])
    assert rev(ctx.repo, "live") == rev(ctx.repo, "origin/main")
    assert rev(Path.join(ctx.repo, ".release"), "HEAD") == rev(ctx.repo, "origin/main")
  end

  test "back is a rollback: refused without --rollback, done with it", ctx do
    assert {_, 0} = release(ctx, ["cut"])
    assert {out, 1} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    assert out =~ "--rollback"
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1"), "--rollback"])
    assert rev(ctx.repo, "live") == rev(ctx.repo, "main~1")
  end

  test "status names what main has that the release doesn't", ctx do
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    assert {out, 0} = release(ctx, ["status"])
    assert out =~ "not released (1)"
    assert out =~ "two"
  end
end
