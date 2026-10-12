defmodule Server.Workline.OperatorReviewTest do
  # The operator reviews a workline's branch in the office: the diff, parsed to files, hunks and
  # line numbers, and a submit of line notes with a verdict. The notes reach the lead as one post in
  # revdiff's shape (`## path:line (+) note`); request changes sends it back to build with them,
  # approve is the gate's approve.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.OperatorReview

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  setup do
    Server.TestDB.clean!()
    root = Path.join(System.tmp_dir!(), "operator-review-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    git(root, ["init", "-q", "-b", "main"])
    git(root, ["config", "user.email", "t@t"])
    git(root, ["config", "user.name", "t"])
    commit(root, "lib/shelf.ex", "a\nb\nc\nd\n")
    commit(root, "lib/gone.ex", "bye\n")
    git(root, ["checkout", "-q", "-b", "work/joys"])
    commit(root, "lib/shelf.ex", "a\nB\nc\nd\ne\n")
    commit(root, "lib/nina.ex", "swat\n")
    git(root, ["rm", "-q", "lib/gone.ex"])
    git(root, ["commit", "-q", "-m", "rm"])
    commit(root, "work/joys/plan.md", "the plan\n")
    git(root, ["checkout", "-q", "main"])
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, root)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  @notes [
    %{"path" => "lib/shelf.ex", "line" => 2, "side" => "+", "text" => "capital B is a typo"},
    %{"path" => "lib/gone.ex", "line" => 1, "side" => "-", "text" => "don't remove this"},
    %{"path" => "lib/nina.ex", "text" => "Nina needs a test"}
  ]

  defp git(root, args), do: {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)

  defp commit(root, path, text) do
    File.mkdir_p!(Path.dirname(Path.join(root, path)))
    File.write!(Path.join(root, path), text)
    git(root, ["add", path])
    git(root, ["commit", "-q", "-m", path])
  end

  defp at_review do
    roster = [
      %{"archetype" => "builder", "name" => "emma"},
      %{"archetype" => "reviewer", "name" => "lonnrot"}
    ]

    {:ok, ws} = Server.Workspaces.register(%{name: "Review", roster: roster})
    {:ok, built} = Workline.open(%{title: "the small joys", slug: "joys", stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(built.id, "emma")
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, built.id), artifacts: AllPresent)
    {:ok, reviewing} = Workline.advance(verifying, artifacts: AllPresent)
    reviewing
  end

  defp bodies(thread), do: thread |> Channel.thread_messages() |> Enum.map(& &1.body)

  test "the diff: each file the branch changes, with its status, counts and numbered lines; its own docs left out",
       %{root: root} do
    thread = at_review()
    review = OperatorReview.diff(thread)

    {head, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/joys"])
    assert review.head == String.trim(head)

    assert Enum.map(review.files, &{&1.path, &1.status, &1.added, &1.deleted}) ==
             [{"lib/gone.ex", "deleted", 0, 1}, {"lib/nina.ex", "added", 1, 0}, {"lib/shelf.ex", "modified", 2, 1}]

    [hunk] = Enum.find(review.files, &(&1.path == "lib/shelf.ex")).hunks
    assert hunk.header =~ "@@ -1,4 +1,5 @@"

    assert Enum.map(hunk.lines, &{&1.kind, &1.old, &1.new, &1.text}) == [
             {" ", 1, 1, "a"},
             {"-", 2, nil, "b"},
             {"+", nil, 2, "B"},
             {" ", 3, 3, "c"},
             {" ", 4, 4, "d"},
             {"+", nil, 5, "e"}
           ]
  end

  test "comment: the notes reach the lead as one post in revdiff's shape; the workline stays where it is" do
    thread = at_review()
    lead = Channel.thread_lead(thread.id)

    assert {:ok, %Thread{stage: "review"}} = OperatorReview.submit(thread, "andrew", "comment", "a few nits", @notes)

    [post] = thread |> bodies() |> Enum.filter(&(&1 =~ "a few nits"))
    assert post =~ "@#{lead}"
    assert post =~ "## lib/shelf.ex:2 (+) capital B is a typo"
    assert post =~ "## lib/gone.ex:1 (-) don't remove this"
    assert post =~ "## lib/nina.ex Nina needs a test"
  end

  test "request changes: back to build with the notes as the why, told to the builder in the brief" do
    thread = at_review()

    assert {:ok, %Thread{stage: "build"}} = OperatorReview.submit(thread, "andrew", "changes", "not yet", @notes)
    assert Channel.thread_lead(thread.id) == "emma"

    brief = thread |> bodies() |> Enum.find(&(&1 =~ "back to build"))
    assert brief =~ "not yet"
    assert brief =~ "## lib/shelf.ex:2 (+) capital B is a typo"
  end

  test "request changes on a workline already at build is a comment: there is nowhere back to send it" do
    roster = [%{"archetype" => "builder", "name" => "emma"}]
    {:ok, ws} = Server.Workspaces.register(%{name: "Building", roster: roster})
    {:ok, built} = Workline.open(%{title: "the small joys", slug: "joys", stage: "build", workspace_id: ws.id})

    assert {:ok, %Thread{stage: "build"}} =
             OperatorReview.submit(built, "andrew", "changes", "while you're in there", @notes)

    assert built |> bodies() |> Enum.any?(&(&1 =~ "## lib/nina.ex Nina needs a test"))
  end

  test "approve: the notes are posted, then the gate is approved; nothing to say is fine too" do
    thread = at_review()
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)

    assert {:ok, %Thread{awaiting: nil}} =
             OperatorReview.submit(parked, "andrew", "approve", "", [hd(@notes)], artifacts: AllPresent)

    assert thread |> bodies() |> Enum.any?(&(&1 =~ "## lib/shelf.ex:2 (+) capital B is a typo"))
  end

  test "an unknown verdict or a comment with nothing in it is refused" do
    thread = at_review()
    assert {:error, :unknown_verdict} = OperatorReview.submit(thread, "andrew", "lgtm", "", @notes)
    assert {:error, :nothing_to_say} = OperatorReview.submit(thread, "andrew", "comment", "  ", [])
  end
end
