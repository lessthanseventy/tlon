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

    tmp = Path.join(System.tmp_dir!(), "workline-review-#{System.pid()}-#{System.unique_integer([:positive])}")
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
    assert {:ok, "work/fence-test/review.md"} =
             Review.submit(thread(), "## Verdict: approve\n\nclean", "menard-machine")

    assert File.read!(Path.join(root, "work/fence-test/review.md")) =~ "Verdict: approve"
    {out, 0} = System.cmd("git", ["-C", root, "log", "--oneline", "-1"], stderr_to_stdout: true)
    assert out =~ "fence-test"

    assert {:ok, _} = Artifacts.Git.check(thread(), {:file, "review.md"})
  end

  test "with the workline's branch there, review.md lands on it — never on the main checkout's branch", %{root: root} do
    git = fn args -> System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
    File.write!(Path.join(root, "seed"), "s")
    {_, 0} = git.(["add", "seed"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = git.(["branch", "work/fence-test"])
    {main_before, 0} = git.(["rev-parse", "HEAD"])

    {:ok, _} = Review.submit(thread(), "## Verdict: approve\n\nclean", "lonnrot")

    assert git.(["rev-parse", "HEAD"]) == {main_before, 0}
    assert {"## Verdict: approve" <> _, 0} = git.(["show", "work/fence-test:work/fence-test/review.md"])

    assert {:ok, "committed work/fence-test/review.md on work/fence-test"} =
             Artifacts.Git.check(thread(), {:file, "review.md"})
  end

  test "the review gate says what there is to decide on: the verdict line and the change's size", %{root: root} do
    git = fn args -> System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
    File.write!(Path.join(root, "seed"), "s")
    {_, 0} = git.(["add", "seed"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = git.(["branch", "work/fence-test"])
    {_, 0} = git.(["checkout", "-q", "work/fence-test"])
    File.write!(Path.join(root, "lib.ex"), "code\n")
    {_, 0} = git.(["add", "lib.ex"])
    {_, 0} = git.(["commit", "-qm", "code"])
    {_, 0} = git.(["checkout", "-q", "-"])
    {:ok, _} = Review.submit(thread(), "## Verdict: APPROVE — clean, one nit\n\ndetails", "lonnrot")

    summary = Server.Workline.gate_summary(thread())
    assert summary =~ "Verdict: APPROVE — clean, one nit"
    assert summary =~ "1 file changed"
  end

  test "a stage doc committed on the workline's branch counts — where its lead, in the worktree, commits it", %{
    root: root
  } do
    git = fn args -> System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
    File.write!(Path.join(root, "seed"), "s")
    {_, 0} = git.(["add", "seed"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = git.(["checkout", "-qb", "work/fence-test"])
    File.mkdir_p!(Path.join(root, "work/fence-test"))
    File.write!(Path.join(root, "work/fence-test/intent.md"), "the ask")
    {_, 0} = git.(["add", "work/fence-test/intent.md"])
    {_, 0} = git.(["commit", "-qm", "intent"])
    {_, 0} = git.(["checkout", "-q", "-"])

    assert {:ok, _} = Artifacts.Git.check(thread("intent"), {:file, "intent.md"})
    assert {:error, _} = Artifacts.Git.check(thread("spec"), {:file, "spec.md"})
  end

  test "build is owed code: a branch carrying only the workline's docs is not built", %{root: root} do
    git = fn args -> System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
    File.write!(Path.join(root, "seed"), "s")
    {_, 0} = git.(["add", "seed"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = git.(["branch", "-M", "main"])
    {_, 0} = git.(["checkout", "-qb", "work/fence-test"])
    File.mkdir_p!(Path.join(root, "work/fence-test"))
    File.write!(Path.join(root, "work/fence-test/spec.md"), "spec")
    {_, 0} = git.(["add", "work"])
    {_, 0} = git.(["commit", "-qm", "spec"])

    assert {:error, why} = Artifacts.Git.check(thread("build"), :branch)
    assert why =~ "no code"

    # a doc first committed at the root, then moved under work/<slug>/: on net, still only docs
    File.write!(Path.join(root, "plan.md"), "plan")
    {_, 0} = git.(["add", "plan.md"])
    {_, 0} = git.(["commit", "-qm", "plan at the root"])
    {_, 0} = git.(["mv", "plan.md", "work/fence-test/plan.md"])
    {_, 0} = git.(["commit", "-qm", "plan moved"])
    {_, 0} = git.(["checkout", "-q", "main"])
    assert {:error, _} = Artifacts.Git.check(thread("build"), :branch)
    {_, 0} = git.(["checkout", "-q", "work/fence-test"])

    File.write!(Path.join(root, "lib.ex"), "code")
    {_, 0} = git.(["add", "lib.ex"])
    {_, 0} = git.(["commit", "-qm", "code"])
    {_, 0} = git.(["checkout", "-q", "main"])
    assert {:ok, _} = Artifacts.Git.check(thread("build"), :branch)
  end

  test "verify's evidence counts only since the workline last entered verify — a bounce leaves none" do
    {:ok, t} = Server.Workline.open(%{title: "v", slug: "fresh-evidence", stage: "verify"})
    corr = "workline:#{t.slug}:verify"

    entered = fn ->
      Server.Dossier.record_event(%{
        thread_id: t.id,
        kind: "stage_advanced",
        correlation: "workline:#{t.slug}",
        detail: %{"from" => "build", "to" => "verify"}
      })
    end

    passed = fn ->
      Server.Dossier.record_check(%{thread_id: t.id, cmd: "mise run check", exit: 0, tail: "", correlation: corr})
    end

    {:ok, _} = entered.()
    {:ok, _} = passed.()
    assert {:ok, _} = Artifacts.Git.check(t, :checks)

    # bounced to build and back: the old green is about code that has changed since
    {:ok, _} = entered.()
    assert {:error, _} = Artifacts.Git.check(t, :checks)

    {:ok, _} = passed.()
    assert {:ok, _} = Artifacts.Git.check(t, :checks)
  end

  test "resubmitting identical content is fine — the artifact is already committed" do
    {:ok, _} = Review.submit(thread(), "same words", "menard-machine")
    assert {:ok, _} = Review.submit(thread(), "same words", "menard-machine")
  end

  test "submit is refused outside the review stage" do
    assert {:error, {:not_in_review, "build"}} = Review.submit(thread("build"), "early!", "menard-machine")
  end

  test "a thread with a project checks and commits in THAT repo, not the workline root" do
    other = Path.join(System.tmp_dir!(), "workline-other-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(other)
    on_exit(fn -> File.rm_rf!(other) end)

    for args <- [
          ~w(init -q),
          ~w(config user.email test@test),
          ~w(config user.name test),
          ~w(commit -q --allow-empty -m root),
          ~w(checkout -qb work/fence-test)
        ] do
      {_, 0} = System.cmd("git", ["-C", other | args], stderr_to_stdout: true)
    end

    File.write!(Path.join(other, "lib.ex"), "code")

    for args <- [~w(add lib.ex), ~w(commit -qm code), ~w(checkout -q -)],
        do: {_, 0} = System.cmd("git", ["-C", other | args], stderr_to_stdout: true)

    {:ok, ws} = Server.Workspaces.register(%{name: "Elsewhere"})

    {:ok, project} =
      Server.Projects.register(%{workspace_id: ws.id, name: "other", repos: [%{"name" => "other", "path" => other}]})

    thread = struct!(thread(), %{project_id: project.id, workspace_id: ws.id})

    assert {:ok, "work/fence-test @ " <> _} = Artifacts.Git.check(thread, :branch)
    assert {:ok, _} = Review.submit(thread, "## Verdict: approve", "menard-machine")

    assert {"## Verdict: approve" <> _, 0} =
             System.cmd("git", ["-C", other, "show", "work/fence-test:work/fence-test/review.md"],
               stderr_to_stdout: true
             )
  end
end
