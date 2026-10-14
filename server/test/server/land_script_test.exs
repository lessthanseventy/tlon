defmodule Server.LandScriptTest do
  # scripts/land.sh, `mise run land -- <pr>`: what GitHub says the PR is, refused here when it can never
  # land, else handed to the server's merge queue by its branch (`tlon-cli land-pr`). gh and tlon-cli
  # stubbed, each recording its calls.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/land.sh", __DIR__)

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    stub!(tmp, "gh", ~S"""
    echo "gh $*" >>"$LOG"
    case "$1 $2" in
      "pr view") echo "${FAKE_PR:-feature main OPEN false}" ;;
      "api repos/{owner}/{repo}/branches/"*) echo "${FAKE_PROTECTED:-false}" ;;
    esac
    """)

    stub!(tmp, "tlon-cli", ~S(echo "tlon-cli $*" >>"$LOG"; echo queued))
    %{tmp: tmp, log: Path.join(tmp, "calls.log")}
  end

  defp stub!(dir, name, body) do
    File.write!(Path.join(dir, name), "#!/bin/sh\n#{body}\n")
    File.chmod!(Path.join(dir, name), 0o755)
  end

  defp land(ctx, env \\ []) do
    env =
      [{"PATH", "#{ctx.tmp}:#{System.get_env("PATH")}"}, {"LOG", ctx.log}, {"TLON_CLI", Path.join(ctx.tmp, "tlon-cli")}] ++
        env

    System.cmd("bash", [@script, "7"], env: env, stderr_to_stdout: true)
  end

  defp calls(ctx), do: if(File.exists?(ctx.log), do: File.read!(ctx.log), else: "")

  test "an open PR onto main from its own branch is handed to the merge queue by its branch", ctx do
    assert {out, 0} = land(ctx)
    assert calls(ctx) =~ "tlon-cli land-pr 7 feature"
    assert out =~ "queued"
  end

  test "refused before it is queued: closed, not onto main, a fork, main itself, a protected branch", ctx do
    for {env, said} <- [
          {[{"FAKE_PR", "feature main MERGED false"}], "MERGED"},
          {[{"FAKE_PR", "feature next OPEN false"}], "next"},
          {[{"FAKE_PR", "feature main OPEN true"}], "fork"},
          {[{"FAKE_PR", "main main OPEN false"}], "main"},
          {[{"FAKE_PROTECTED", "true"}], "protected"}
        ] do
      assert {out, 1} = land(ctx, env)
      assert out =~ said
    end

    refute calls(ctx) =~ "land-pr"
  end
end
