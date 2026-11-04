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

    File.cp!(
      Path.expand("../../../scripts/git-fetch-origin.sh", __DIR__),
      Path.join(repo, "scripts/git-fetch-origin.sh")
    )

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

  test "a cut from a citizen pane (TLON_THREAD set) still pushes live past the pre-push fence", ctx do
    hook = Path.join(ctx.repo, ".git/hooks/pre-push")
    File.cp!(Path.expand("../../../scripts/git-hooks/pre-push", __DIR__), hook)
    File.chmod!(hook, 0o755)

    assert {out, 0} = release(ctx, ["cut"], [{"TLON_THREAD", "269"}])
    refute out =~ "the push to origin failed"
    assert rev(ctx.repo, "origin/live") == rev(ctx.repo, "live")
  end

  test "a push that fails says why", ctx do
    sh!(ctx.repo, "git remote set-url --push origin /nonexistent/origin.git")

    assert {out, 0} = release(ctx, ["cut"])
    assert out =~ "the push to origin failed"
    assert out =~ "nonexistent"
  end

  test "--no-restart cuts and builds but leaves the restart to the caller", ctx do
    File.write!(Path.join(ctx.bin, "curl"), ~s{#!/bin/sh\necho called >> "$(dirname "$0")/curl.log"\n})

    assert {out, 0} = release(ctx, ["cut", "--no-restart"])
    refute out =~ "restart:"
    refute File.exists?(Path.join(ctx.bin, "curl.log"))
    assert rev(ctx.repo, "live") == rev(ctx.repo, "origin/main")
  end

  describe "a cut that changes nothing the server runs" do
    setup ctx do
      {_, 0} = release(ctx, ["cut"])
      release_bin = Path.join(ctx.repo, ".release/server/_build/prod/rel/server/bin/server")
      File.mkdir_p!(Path.dirname(release_bin))
      File.write!(release_bin, "")
      File.chmod!(release_bin, 0o755)

      for {name, body} <- [
            {"mix", "echo mix >> #{ctx.bin}/calls"},
            {"curl", ~s(echo "$@" >> #{ctx.bin}/calls; echo '{}')}
          ] do
        File.write!(Path.join(ctx.bin, name), "#!/bin/sh\n#{body}\n")
      end

      %{calls: Path.join(ctx.bin, "calls")}
    end

    defp push!(ctx, file) do
      File.mkdir_p!(Path.dirname(Path.join(ctx.repo, file)))
      File.write!(Path.join(ctx.repo, file), "changed\n")
      sh!(ctx.repo, "git add -A -- #{file} && git commit -qm change && git push -q origin main")
    end

    test "moves the checkout, builds nothing, restarts nothing and says it is live", ctx do
      push!(ctx, "adapters/claude-code/launch.sh")

      assert {out, 0} = release(ctx, ["cut"])
      assert out =~ "restart: not needed"
      assert rev(ctx.repo, "live") == rev(ctx.repo, "origin/main")
      assert rev(Path.join(ctx.repo, ".release"), "HEAD") == rev(ctx.repo, "origin/main")

      calls = File.read!(ctx.calls)
      refute calls =~ "mix"
      refute calls =~ "/api/restart"
      assert calls =~ "/api/live"
    end

    test "--no-restart says so and leaves saying it is live to the caller", ctx do
      push!(ctx, "scripts/a-script.sh")

      assert {out, 0} = release(ctx, ["cut", "--no-restart"])
      assert out =~ "restart: not needed"
      refute File.exists?(ctx.calls)
    end

    test "a server the script can't reach is restarted: down is what needs it", ctx do
      push!(ctx, "scripts/a-script.sh")
      File.write!(Path.join(ctx.bin, "curl"), "#!/bin/sh\nexit 7\n")
      restart = Path.join(ctx.repo, "scripts/server-restart.sh")
      File.write!(restart, "#!/bin/sh\necho \"restarted $@\" >> #{ctx.calls}\n")
      File.chmod!(restart, 0o755)

      assert {_, 0} = release(ctx, ["cut"])
      assert rev(ctx.repo, "live") == rev(ctx.repo, "origin/main")
      assert File.read!(ctx.calls) =~ "restarted --force"
    end

    for file <- ["server/lib/a.ex", "mise.toml"] do
      test "a change to #{file} builds and restarts", ctx do
        push!(ctx, unquote(file))

        assert {out, 0} = release(ctx, ["cut"])
        refute out =~ "not needed"
        calls = File.read!(ctx.calls)
        assert calls =~ "mix"
        assert calls =~ "/api/restart"
      end
    end

    test "a release that was never built is built", ctx do
      push!(ctx, "scripts/a-script.sh")
      File.rm_rf!(Path.join(ctx.repo, ".release/server/_build"))

      assert {out, 0} = release(ctx, ["cut"])
      refute out =~ "not needed"
      assert File.read!(ctx.calls) =~ "mix"
    end

    test "a rollback across a server change builds and restarts", ctx do
      back = rev(ctx.repo, "main")
      push!(ctx, "server/lib/a.ex")
      assert {_, 0} = release(ctx, ["cut"])
      File.rm!(ctx.calls)

      assert {out, 0} = release(ctx, ["cut", back, "--rollback"])
      refute out =~ "not needed"
      assert File.read!(ctx.calls) =~ "/api/restart"
    end
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
