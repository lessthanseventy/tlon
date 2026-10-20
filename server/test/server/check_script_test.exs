defmodule Server.CheckScriptTest do
  # scripts/check.sh, `mise run check`'s body: the gate's verdict posted to GitHub as the commit status
  # tlon/check, only for a commit it tested. Real git; mise and gh stubbed, gh recording its calls.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/check.sh", __DIR__)

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    bin = Path.join(tmp, "bin")
    repo = Path.join(tmp, "repo")
    File.mkdir_p!(bin)
    File.mkdir_p!(repo)
    stub!(bin, "mise", ~s(exit "${FAKE_GATE:-0}"))
    # the verdict already on a commit is FAKE_STATUS; every other call is recorded
    stub!(
      bin,
      "gh",
      ~s(case "$*" in *commits/*/statuses*\) echo "${FAKE_STATUS:-}" ;; *\) echo "$*" >>"$GH_LOG" ;; esac)
    )

    {_, 0} =
      System.cmd(
        "sh",
        [
          "-c",
          "git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m one"
        ],
        cd: repo
      )

    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo)
    %{bin: bin, repo: repo, log: Path.join(tmp, "gh.log"), sha: String.trim(sha)}
  end

  defp stub!(bin, name, body) do
    File.write!(Path.join(bin, name), "#!/bin/sh\n#{body}\n")
    File.chmod!(Path.join(bin, name), 0o755)
  end

  defp check(ctx, env \\ []) do
    env = [{"PATH", "#{ctx.bin}:#{System.get_env("PATH")}"}, {"GH_LOG", ctx.log}, {"TLON_CHECK_STATUS", nil} | env]
    System.cmd("bash", [@script], cd: ctx.repo, env: env, stderr_to_stdout: true)
  end

  defp gh_calls(ctx), do: if(File.exists?(ctx.log), do: File.read!(ctx.log), else: "")

  test "green on a clean tree: tlon/check success posted for HEAD's sha", ctx do
    assert {out, 0} = check(ctx)
    assert gh_calls(ctx) =~ ~r"^api repos/\{owner\}/\{repo\}/statuses/#{ctx.sha} .*state=success.*context=tlon/check"m
    assert out =~ "tlon/check: success posted for #{String.slice(ctx.sha, 0, 12)}"
  end

  test "red on a clean tree: failure posted, the gate's exit kept", ctx do
    assert {_, 3} = check(ctx, [{"FAKE_GATE", "3"}])
    assert gh_calls(ctx) =~ ~r"statuses/#{ctx.sha} .*state=failure.*context=tlon/check"
  end

  test "a clean commit tlon/check already passed is not gated again", ctx do
    assert {out, 0} = check(ctx, [{"FAKE_STATUS", "success"}, {"FAKE_GATE", "3"}])
    assert out =~ "already success for #{String.slice(ctx.sha, 0, 12)}"
    assert gh_calls(ctx) == ""
  end

  test "a commit whose last verdict was a failure is gated again", ctx do
    assert {_, 0} = check(ctx, [{"FAKE_STATUS", "failure"}])
    assert gh_calls(ctx) =~ ~r"statuses/#{ctx.sha} .*state=success"
  end

  test "TLON_CHECK_FORCE=1 gates a commit that already passed", ctx do
    assert {_, 3} = check(ctx, [{"FAKE_STATUS", "success"}, {"FAKE_GATE", "3"}, {"TLON_CHECK_FORCE", "1"}])
    assert gh_calls(ctx) =~ ~r"statuses/#{ctx.sha} .*state=failure"
  end

  test "an untracked file: nothing posted, and it says why", ctx do
    File.write!(Path.join(ctx.repo, "stray.txt"), "x")
    assert {out, 0} = check(ctx)
    assert gh_calls(ctx) == ""
    assert out =~ "tlon/check: not posted"
    assert out =~ "uncommitted or untracked"
  end

  test "TLON_CHECK_STATUS=0 posts nothing", ctx do
    assert {out, 0} = check(ctx, [{"TLON_CHECK_STATUS", "0"}])
    assert gh_calls(ctx) == ""
    assert out =~ "TLON_CHECK_STATUS=0"
  end

  test "gh refusing (unauthenticated) is said, never a red gate", ctx do
    stub!(ctx.bin, "gh", ~s(echo "gh auth login first" >&2; exit 4))
    assert {out, 0} = check(ctx)
    assert out =~ "tlon/check: not posted — gh: gh auth login first"
  end
end
