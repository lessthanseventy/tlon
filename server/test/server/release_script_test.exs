defmodule Server.ReleaseScriptTest do
  # scripts/release.sh, the release pointer: only merged work ships, only forward unless rolled back,
  # and a cut leaves .release checked out at the release. Real git; mix, curl and the restart stubbed.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/release.sh", __DIR__)

  # a suite killed mid-test (a gate cut off) never ran its on_exit: its dirs, named after its OS pid,
  # go once that pid is gone
  setup_all do
    for d <- Path.wildcard(Path.join(System.tmp_dir!(), "release-test-*-*")),
        [_, pid] <- [Regex.run(~r/release-test-(\d+)-\d+$/, d)],
        elem(System.cmd("kill", ["-0", pid], stderr_to_stdout: true), 1) != 0,
        do: File.rm_rf(d)

    :ok
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "release-test-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  defp release(%{repo: repo, bin: bin}, args, env \\ []) do
    env = [{"PATH", "#{bin}:#{System.get_env("PATH")}"}, {"TLON_RELEASE_DIR", Path.join(repo, ".release")} | env]
    System.cmd("bash", [Path.join(repo, "scripts/release.sh") | args], cd: repo, env: env, stderr_to_stdout: true)
  end

  defp cli!(%{bin: bin}, body) do
    path = Path.join(bin, "tlon-cli")
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
    [{"TLON_CLI", path}]
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

  test "--no-restart cuts and builds but leaves the restart to the caller", ctx do
    File.write!(Path.join(ctx.bin, "curl"), ~s{#!/bin/sh\necho called >> "$(dirname "$0")/curl.log"\n})

    assert {out, 0} = release(ctx, ["cut", "--no-restart"])
    refute out =~ "restart:"
    refute File.exists?(Path.join(ctx.bin, "curl.log"))
    assert rev(ctx.repo, "live") == rev(ctx.repo, "origin/main")
  end

  test "back is a rollback: refused without --rollback, done with it", ctx do
    assert {_, 0} = release(ctx, ["cut"])
    assert {out, 1} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    assert out =~ "--rollback"
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1"), "--rollback"])
    assert rev(ctx.repo, "live") == rev(ctx.repo, "main~1")
  end

  test "a build that fails leaves live where it was", ctx do
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    File.write!(Path.join(ctx.bin, "mix"), "#!/bin/sh\n[ \"$1\" = release ] && exit 1\nexit 0\n")

    assert {out, 1} = release(ctx, ["cut"])
    assert out =~ "the build failed"
    assert rev(ctx.repo, "live") == rev(ctx.repo, "main~1")
  end

  test "status names what main has that the release doesn't", ctx do
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1")])
    assert {out, 0} = release(ctx, ["status"])
    assert out =~ "not released (1)"
    assert out =~ "two"
  end

  test "status reads origin/main's releasability off the server, and says when it can't", ctx do
    main = rev(ctx.repo, "origin/main")
    assert {_, 0} = release(ctx, ["cut", rev(ctx.repo, "main~1")])

    asked = cli!(ctx, ~s([ "$1 $2" = "releasable #{main}" ] && echo "gate  ✓ passed" && echo "releasable: yes"))
    assert {out, 0} = release(ctx, ["status"], asked)
    assert out =~ "gate  ✓ passed"
    assert out =~ "releasable: yes"

    assert {out, 0} = release(ctx, ["status"], cli!(ctx, "exit 1"))
    assert out =~ "the server didn't answer"
  end
end
