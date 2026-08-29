defmodule Server.WorklineReviewTest do
  # Worklines slice 3: the reviewer's ONE door. The reviewer profile is structurally
  # write-fenced (@reviewer_permissions), so review.md lands through submit_review — funes
  # writes and commits the file itself. The fence stays airtight; the tool is the door.
  use ExUnit.Case, async: false

  alias Server.Thread
  alias Server.Workline.Artifacts
  alias Server.Workline.Review

  setup do
    Server.TestDB.clean!()

    tmp = Path.join(System.tmp_dir!(), "workline-review-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["-C", tmp, "init", "-q"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.email", "test@test"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.name", "test"], stderr_to_stdout: true)

    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    %{root: tmp}
  end

  defp thread(stage \\ "review"), do: struct!(Thread, %{id: 7, title: "t", slug: "fence-test", stage: stage})

  test "submit writes review.md, commits it, and the artifact checker then passes", %{root: root} do
    assert {:ok, "work/fence-test/review.md"} = Review.submit(thread(), "## Verdict: approve\n\nclean", "menard-machine")

    assert File.read!(Path.join(root, "work/fence-test/review.md")) =~ "Verdict: approve"
    {out, 0} = System.cmd("git", ["-C", root, "log", "--oneline", "-1"], stderr_to_stdout: true)
    assert out =~ "fence-test"

    assert {:ok, _} = Artifacts.Git.check(thread(), {:file, "review.md"})
  end

  test "resubmitting identical content is fine — the artifact is already committed" do
    {:ok, _} = Review.submit(thread(), "same words", "menard-machine")
    assert {:ok, _} = Review.submit(thread(), "same words", "menard-machine")
  end

  test "submit is refused outside the review stage" do
    assert {:error, {:not_in_review, "build"}} = Review.submit(thread("build"), "early!", "menard-machine")
  end
end
