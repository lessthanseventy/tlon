defmodule Server.BranchReview.HeadlessTest do
  use ExUnit.Case, async: false

  alias Server.BranchReview
  alias Server.BranchReview.Headless

  @opus "anthropic/claude-opus-5-5"
  @sonnet "anthropic/claude-sonnet-5-5"

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "headless-review-#{System.pid()}-#{System.unique_integer([:positive])}")
    repo = Path.join(dir, "repo")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(dir) end)

    git(repo, ["init", "-q", "-b", "main"])
    commit(repo, "a.txt", "one\n", "the first line")
    git(repo, ["switch", "-q", "-c", "feat"])
    commit(repo, "b.txt", "two\n", "a second file\n\nCo-Authored-By: Sonnet 5.5 <noreply@anthropic.com>")
    {head, 0} = git(repo, ["rev-parse", "HEAD"])
    git(repo, ["switch", "-q", "main"])

    %{dir: dir, repo: repo, head: String.trim(head)}
  end

  defp git(repo, args) do
    env =
      [{"GIT_AUTHOR_NAME", "ada"}, {"GIT_AUTHOR_EMAIL", "a@x"}, {"GIT_COMMITTER_NAME", "ada"}] ++
        [{"GIT_COMMITTER_EMAIL", "a@x"}]

    {_, 0} = System.cmd("git", ["-C", repo | args], env: env, stderr_to_stdout: true)
  end

  defp commit(repo, file, text, message) do
    File.write!(Path.join(repo, file), text)
    git(repo, ["add", file])
    git(repo, ["commit", "-q", "-m", message])
  end

  defp cli(dir, body) do
    path = Path.join(dir, "cli")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  defp unqueued(_repo, _branch), do: {:error, "feat has no open PR"}

  test "an approval is recorded on the head it read, by the model that read it", ctx do
    cmd = cli(ctx.dir, ~s(printf 'reads right\\nVERDICT: approve\\n'))

    assert {:ok, %{verdict: "approve", sha: sha, by: @opus, body: "reads right", landing: landing}} =
             Headless.review(ctx.repo, "feat", cmd: cmd, models: [@opus], land: &unqueued/2)

    assert sha == ctx.head
    assert landing == "not queued: feat has no open PR"
    assert %{verdict: "approve", sha: ^sha, by: @opus, body: "reads right"} = BranchReview.latest("feat")
  end

  test "an approval hands the branch's PR to the merge queue", ctx do
    cmd = cli(ctx.dir, "echo 'VERDICT: approve'")
    land = fn repo, "feat" when repo == ctx.repo -> {:ok, %{args: %{"pr" => 7}}} end

    assert {:ok, %{landing: "queued PR #7"}} = Headless.review(ctx.repo, "feat", cmd: cmd, models: [@opus], land: land)
  end

  test "requested changes are recorded and queue nothing", ctx do
    cmd = cli(ctx.dir, ~s(printf 'b.txt:1 is wrong\\nVERDICT: request_changes\\n'))
    land = fn _repo, _branch -> flunk("a branch with changes requested went to the merge queue") end

    assert {:ok, %{verdict: "request_changes", body: "b.txt:1 is wrong", landing: nil}} =
             Headless.review(ctx.repo, "feat", cmd: cmd, models: [@opus], land: land)

    assert %{verdict: "request_changes"} = BranchReview.latest("feat")
  end

  test "the reviewer is the first model that wrote none of the branch", ctx do
    cmd = cli(ctx.dir, "echo 'VERDICT: approve'")

    assert {:ok, %{by: @opus}} =
             Headless.review(ctx.repo, "feat", cmd: cmd, models: [@sonnet, @opus], land: &unqueued/2)
  end

  test "a branch every reviewer model helped write is refused, nothing recorded", ctx do
    cmd = cli(ctx.dir, "echo 'VERDICT: approve'")

    assert {:error, why} = Headless.review(ctx.repo, "feat", cmd: cmd, models: [@sonnet], land: &unqueued/2)
    assert why =~ "another model's"
    assert BranchReview.latest("feat") == nil
  end

  test "a reply with no verdict line records nothing", ctx do
    cmd = cli(ctx.dir, "echo 'I think it is fine'")

    assert {:error, why} = Headless.review(ctx.repo, "feat", cmd: cmd, models: [@opus], land: &unqueued/2)
    assert why =~ "VERDICT"
    assert BranchReview.latest("feat") == nil
  end

  test "the reviewer reads the diff in a checkout of the head with read-only tools, removed after", ctx do
    seen = Path.join(ctx.dir, "seen")

    cmd =
      cli(ctx.dir, """
      { pwd; echo "$@"; ls; cat; } > #{seen}
      echo 'VERDICT: approve'
      """)

    assert {:ok, _} = Headless.review(ctx.repo, "feat", cmd: cmd, models: [@opus], land: &unqueued/2)

    [checkout, args | rest] = seen |> File.read!() |> String.split("\n")
    assert args =~ "--tools Read,Grep,Glob"
    assert args =~ "--setting-sources user"
    assert "b.txt" in rest
    assert "+two" in rest
    assert Enum.any?(rest, &(&1 =~ ctx.head))
    refute File.exists?(checkout)
  end

  test "a branch that changes nothing is refused, nothing recorded", ctx do
    git(ctx.repo, ["branch", "same", "main"])
    cmd = cli(ctx.dir, "echo 'VERDICT: approve'")

    assert {:error, why} = Headless.review(ctx.repo, "same", cmd: cmd, models: [@opus], land: &unqueued/2)
    assert why =~ "nothing to review"
    assert BranchReview.latest("same") == nil
  end

  test "main is never reviewed", ctx do
    assert {:error, why} = Headless.review(ctx.repo, "main", models: [@opus])
    assert why =~ "main"
  end
end
