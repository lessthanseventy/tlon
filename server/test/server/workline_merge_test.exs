defmodule Server.Workline.MergeTest do
  # Approving a review lands the workline's branch: rebased onto origin's main and gated there, for
  # GitHub to merge. The checkout people work in is never moved — its main follows origin on its own.
  # Real git, temp repos with a bare origin.
  use ExUnit.Case, async: true

  alias Server.Workline.Merge

  setup do
    repo = Path.join(System.tmp_dir!(), "merge-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    remote = repo <> "-remote.git"
    other = repo <> "-other"
    File.mkdir_p!(repo)
    on_exit(fn -> Enum.each([repo, remote, other, repo <> "-wt"], &File.rm_rf!/1) end)
    git = fn args -> System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    {_, 0} = git.(["init", "-q", "-b", "main"])
    {_, 0} = git.(["config", "user.email", "t@t"])
    {_, 0} = git.(["config", "user.name", "t"])
    File.write!(Path.join(repo, "a.txt"), "one\n")
    {_, 0} = git.(["add", "a.txt"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = System.cmd("git", ["init", "-q", "--bare", "-b", "main", remote])
    {_, 0} = git.(["remote", "add", "origin", remote])
    {_, 0} = git.(["push", "-q", "-u", "origin", "main"])
    {_, 0} = System.cmd("git", ["clone", "-q", remote, other])
    {_, 0} = git.(["checkout", "-qb", "work/finder"])
    File.write!(Path.join(repo, "b.txt"), "built\n")
    {_, 0} = git.(["add", "b.txt"])
    {_, 0} = git.(["commit", "-qm", "build"])
    {_, 0} = git.(["checkout", "-q", "main"])
    %{repo: repo, git: git, other: other}
  end

  # something lands on GitHub's main that this machine has not fetched
  defp land_upstream(other, file, text, subject) do
    File.write!(Path.join(other, file), text)

    for args <- [["add", file], ~w(-c user.email=t@t -c user.name=t commit -qm) ++ [subject], ~w(push -q origin main)],
        do: {_, 0} = System.cmd("git", ["-C", other | args], stderr_to_stdout: true)

    {sha, 0} = System.cmd("git", ["-C", other, "rev-parse", "HEAD"])
    String.trim(sha)
  end

  defp sha(git, ref) do
    {out, 0} = git.(["rev-parse", ref])
    String.trim(out)
  end

  defp subjects(git, ref) do
    {out, 0} = git.(["log", "--format=%s", ref])
    String.split(out, "\n", trim: true)
  end

  test "rebases work/<slug> onto origin's main and says what moved; local main never moves", %{
    repo: repo,
    git: git,
    other: other
  } do
    main_before = sha(git, "main")
    upstream = land_upstream(other, "theirs.txt", "from github\n", "theirs")

    assert {:ok, %{from: ^upstream, to: to}} = Merge.merge(repo, "finder")
    assert to == sha(git, "work/finder")
    assert subjects(git, "work/finder") == ["build", "theirs", "seed"]
    assert {"", 0} = git.(["rev-list", "--merges", "work/finder"])
    assert sha(git, "main") == main_before
    refute File.exists?(Path.join(repo, "b.txt"))
  end

  test "this machine's copies of what GitHub merged drop out of the rebased branch", %{
    git: git,
    repo: repo,
    other: other
  } do
    # GitHub rebase-merged a change, so origin has it under another id than local main does
    _ = land_upstream(other, "c.txt", "meanwhile\n", "meanwhile")
    File.write!(Path.join(repo, "c.txt"), "meanwhile\n")
    {_, 0} = git.(["add", "c.txt"])
    {_, 0} = git.(["commit", "-qm", "meanwhile (local copy)"])
    {_, 0} = git.(["rebase", "-q", "main", "work/finder"])
    {_, 0} = git.(["checkout", "-q", "main"])

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert subjects(git, "work/finder") == ["build", "meanwhile", "seed"]
  end

  test "a gate runs on the rebased branch; red, the branch keeps its rebase and main stays", %{
    repo: repo,
    git: git,
    other: other
  } do
    _ = land_upstream(other, "c.txt", "meanwhile\n", "meanwhile on main")
    main_before = sha(git, "main")
    me = self()

    red = fn r, branch ->
      {log, 0} = System.cmd("git", ["-C", r, "log", "--format=%s", branch])
      send(me, {:gated, log})
      {:error, "the gate is red"}
    end

    assert {:error, "the gate is red"} = Merge.merge(repo, "finder", gate: red)
    assert_received {:gated, log}
    assert log =~ "build" and log =~ "meanwhile on main"
    assert sha(git, "main") == main_before
  end

  test "a branch checked out in its own worktree is rebased there", %{repo: repo, git: git, other: other} do
    wt = repo <> "-wt"
    {_, 0} = git.(["worktree", "add", "-q", wt, "work/finder"])
    _ = land_upstream(other, "c.txt", "meanwhile\n", "meanwhile on main")

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert File.read!(Path.join(wt, "c.txt")) == "meanwhile\n"
  end

  test "the live checkout's own state is not its business: dirty, or on another branch, it lands and nothing there moves",
       %{repo: repo, git: git} do
    {_, 0} = git.(["checkout", "-qb", "elsewhere"])
    File.write!(Path.join(repo, "a.txt"), "edited\n")
    head = sha(git, "HEAD")

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert {"elsewhere\n", 0} = git.(["symbolic-ref", "--short", "HEAD"])
    assert sha(git, "HEAD") == head
    assert File.read!(Path.join(repo, "a.txt")) == "edited\n"
  end

  test "a conflict is aborted, leaving main and the branch as they were", %{repo: repo, git: git, other: other} do
    {_, 0} = git.(["checkout", "-q", "work/finder"])
    File.write!(Path.join(repo, "a.txt"), "theirs\n")
    {_, 0} = git.(["commit", "-qam", "theirs"])
    {_, 0} = git.(["checkout", "-q", "main"])
    _ = land_upstream(other, "a.txt", "ours\n", "ours")
    head = sha(git, "HEAD")
    tip = sha(git, "work/finder")

    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "conflict" and why =~ "a.txt"
    refute why =~ "hint:"
    assert sha(git, "HEAD") == head
    assert sha(git, "work/finder") == tip
    assert {"", 0} = git.(["status", "--porcelain"])
  end

  test "a branch that isn't there is refused", %{repo: repo} do
    assert {:error, why} = Merge.merge(repo, "nope")
    assert why =~ "work/nope"
  end

  test "a git step that fails says what git said, not only which step", %{repo: repo, git: git} do
    {_, 0} = git.(["remote", "set-url", "origin", repo <> "-nowhere.git"])
    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "could not fetch origin"
    assert why =~ "nowhere.git"
  end

  test "a repo with no origin has nowhere to land", %{repo: repo, git: git} do
    {_, 0} = git.(["remote", "remove", "origin"])
    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "no origin"
  end

  describe "golden frames (office/test/golden.json)" do
    # both sides re-hash the room's frames, so the file conflicts on every rebase; a landing takes
    # origin's side and re-hashes afterwards instead of bouncing
    setup %{repo: repo, git: git, other: other} do
      golden = "office/test/golden.json"
      File.mkdir_p!(Path.join(repo, "office/test"))
      File.write!(Path.join(repo, golden), "base\n")
      {_, 0} = git.(["add", golden])
      {_, 0} = git.(["commit", "-qm", "golden"])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = System.cmd("git", ["-C", other, "pull", "-q"], stderr_to_stdout: true)
      {_, 0} = git.(["checkout", "-q", "work/finder"])
      {_, 0} = git.(["rebase", "-q", "main"])
      File.write!(Path.join(repo, "office/room.ts"), "moved\n")
      File.write!(Path.join(repo, golden), "ours\n")
      {_, 0} = git.(["add", "office"])
      {_, 0} = git.(["commit", "-qm", "office: move the room"])
      File.write!(Path.join(repo, golden), "ours again\n")
      {_, 0} = git.(["commit", "-qam", "office: re-hash"])
      {_, 0} = git.(["checkout", "-q", "main"])
      me = self()

      rehash = fn tree ->
        send(me, {:rehashed, tree})
        File.write!(Path.join(tree, golden), "rehashed\n")
        {:ok, :rehashed}
      end

      %{golden: golden, rehash: rehash}
    end

    test "a conflict only on golden.json takes origin's side, then the frames are re-hashed and committed", %{
      repo: repo,
      git: git,
      other: other,
      golden: golden,
      rehash: rehash
    } do
      _ = land_upstream(other, golden, "theirs\n", "office: theirs")

      assert {:ok, %{to: to}} = Merge.merge(repo, "finder", rehash: rehash)
      assert_received {:rehashed, _}
      assert {"rehashed\n", 0} = git.(["show", "work/finder:" <> golden])
      assert to == sha(git, "work/finder")

      # the branch's own re-hash commit is empty on origin's side, so it drops out
      assert subjects(git, "work/finder") == [
               "office: re-hash the golden frames on landing",
               "office: move the room",
               "build",
               "office: theirs",
               "golden",
               "seed"
             ]
    end

    test "any other conflict beside it still aborts", %{
      repo: repo,
      git: git,
      other: other,
      golden: golden,
      rehash: rehash
    } do
      {_, 0} = git.(["checkout", "-q", "work/finder"])
      File.write!(Path.join(repo, "a.txt"), "mine\n")
      {_, 0} = git.(["commit", "-qam", "a mine"])
      {_, 0} = git.(["checkout", "-q", "main"])
      tip = sha(git, "work/finder")
      _ = land_upstream(other, golden, "theirs\n", "office: theirs")
      _ = land_upstream(other, "a.txt", "theirs\n", "a theirs")

      assert {:error, why} = Merge.merge(repo, "finder", rehash: rehash)
      assert why =~ "conflict" and why =~ "a.txt"
      refute_received {:rehashed, _}
      assert sha(git, "work/finder") == tip
    end

    test "a branch that never touched office/ isn't re-hashed", %{repo: repo, git: git, rehash: rehash} do
      {_, 0} = git.(["branch", "-qf", "work/finder", "main"])
      {_, 0} = git.(["checkout", "-q", "work/finder"])
      File.write!(Path.join(repo, "c.txt"), "elsewhere\n")
      {_, 0} = git.(["add", "c.txt"])
      {_, 0} = git.(["commit", "-qm", "elsewhere"])
      {_, 0} = git.(["checkout", "-q", "main"])

      assert {:ok, _} = Merge.merge(repo, "finder", rehash: rehash)
      refute_received {:rehashed, _}
    end
  end
end
