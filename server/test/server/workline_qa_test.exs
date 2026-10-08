defmodule Server.WorklineQATest do
  # Roster design §5, step 6: a reviewed change Andrew would see goes to the qa seat before it can
  # land; the QA run (stubbed here as what the seat files) passes it on to the merge gate or sends
  # it back to build with its finding.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  @low_scores %{"scope" => 1, "reversibility" => 1, "blast" => 1, "detectability" => 1, "proof" => 1}
  @checked Map.new(
             ~w(scope reversibility blast detectability proof),
             &{&1, %{"why" => "fine", "kind" => "fact", "quote" => "q", "grounded" => true}}
           )
  @low %{"limits" => [], "decisions" => [], "scores" => @low_scores, "reasons" => @checked}

  @broken_r """
  === after: R
   HOME   #12 office: R relaunches
   R reloads — the office and its server disagree
  """

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    :ok
  end

  # a workline at review on a bench with a builder, a reviewer and (unless left out) a qa seat
  defp at_review(slug, paths, opts \\ []) do
    roster =
      [
        %{"archetype" => "builder", "name" => "emma"},
        %{"archetype" => "reviewer", "name" => "lonnrot"}
      ] ++ if(Keyword.get(opts, :qa, true), do: [%{"archetype" => "qa", "name" => "nolan"}], else: [])

    {:ok, ws} = Server.Workspaces.register(%{name: "QA #{slug}", roster: roster})
    {:ok, built} = Workline.open(%{title: "office: #{slug}", slug: slug, stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(built.id, "emma")
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, built.id), artifacts: AllPresent)
    {:ok, reviewing} = Workline.advance(verifying, artifacts: AllPresent)

    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: reviewing.id,
        kind: "check_passed",
        correlation: "workline:#{slug}:grade",
        detail: @low
      })

    {reviewing, [artifacts: AllPresent, paths: paths, auto_land_risk: 5]}
  end

  defp bodies(thread), do: thread |> Channel.thread_messages() |> Enum.map(& &1.body)

  test "a driven workline with a broken R gets a QA finding before it lands" do
    {thread, opts} = at_review("broken-r", ["office/tui/main.ts"])

    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    assert Channel.thread_lead(thread.id) == "nolan"
    brief = thread |> bodies() |> Enum.find(&(&1 =~ "release:smoke"))
    assert brief =~ "work/broken-r"
    assert brief =~ "submit_qa"

    # the reviewer's hand-on to the merge gate waits on QA, even under a standing approval
    assert {:error, {:artifact_missing, why}} = Workline.advance(Repo.get!(Thread, thread.id), opts)
    assert why =~ "QA"
    refute_enqueued(worker: Server.Jobs.Land)

    assert {:error, {:bounced, _}} =
             Workline.qa_verdict(Repo.get!(Thread, thread.id), "fail", "nolan", @broken_r, opts)

    assert %Thread{stage: "build", awaiting: nil, state: "open"} = Repo.get!(Thread, thread.id)
    assert Channel.thread_lead(thread.id) == "emma"

    assert Enum.any?(
             bodies(thread),
             &(&1 =~ "back to build" and &1 =~ "R reloads — the office and its server disagree")
           )

    refute_enqueued(worker: Server.Jobs.Land)
  end

  test "a QA pass hands it on to the merge gate" do
    {thread, opts} = at_review("r-reloads", ["server/lib/server/mcp/operator_api.ex"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)

    assert {:ok, %Thread{stage: "review", awaiting: nil}} =
             Workline.qa_verdict(Repo.get!(Thread, thread.id), "pass", "nolan", "=== after: R\n HOME", opts)

    assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: thread.id})
    assert Enum.any?(bodies(thread), &(&1 =~ "QA passed" and &1 =~ "HOME"))
  end

  test "an operator's approve can't land it past an owed QA" do
    {thread, opts} = at_review("held", ["office/kit/room.ts"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    {:ok, held} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()

    assert {:error, {:artifact_missing, why}} = Workline.approve(held, Keyword.put(opts, :land, :queue))
    assert why =~ "QA"
    assert {:ok, %{awaiting: "andrew"}} = Workline.graded(held, opts)
    refute_enqueued(worker: Server.Jobs.Land)
  end

  test "the operator's approve skips an owed QA only when told to, with a reason, and says so" do
    {thread, opts} = at_review("overridden", ["office/kit/room.ts"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    opts = Keyword.put(opts, :land, :queue)

    assert {:error, :nothing_awaiting} = Workline.approve(Repo.get!(Thread, thread.id), opts)

    assert {:error, :nothing_awaiting} =
             Workline.approve(Repo.get!(Thread, thread.id), Keyword.put(opts, :skip_qa, " "))

    refute_enqueued(worker: Server.Jobs.Land)

    assert {:ok, %Thread{stage: "review", awaiting: nil}} =
             Workline.approve(Repo.get!(Thread, thread.id), Keyword.put(opts, :skip_qa, "no display on this box"))

    assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: thread.id})

    assert [%{kind: "check_passed", detail: %{"tail" => "skipped by the operator: no display on this box"}}] =
             Repo.all(
               from e in Server.Event, where: e.thread_id == ^thread.id and e.correlation == "workline:overridden:qa"
             )

    assert Enum.any?(bodies(thread), &(&1 =~ "QA skipped by the operator" and &1 =~ "no display on this box"))
  end

  test "a parked gate's approve skips an owed QA the same way" do
    {thread, opts} = at_review("parked-override", ["office/kit/room.ts"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    {:ok, held} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()

    assert {:ok, %Thread{awaiting: nil}} =
             Workline.approve(held, opts ++ [land: :queue, skip_qa: "drove it myself"])

    assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: thread.id})
  end

  test "while QA is owed, the qa seat's brief and nudges are QA's, not the reviewer's" do
    {thread, opts} = at_review("qa-led", ["office/tui/main.ts"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    led = Repo.get!(Thread, thread.id)

    assert {:error, why} = Workline.owed_status(led, opts)
    assert why =~ "submit_qa" and why =~ "release:smoke"
    refute why =~ "submit_review"

    :ok = Server.Workline.Continuation.run(led.id, opts)
    nudge = thread |> bodies() |> Enum.find(&String.starts_with?(&1, "↻"))
    assert nudge =~ "submit_qa"
    refute nudge =~ "advance_stage" or nudge =~ "submit_review"

    {:ok, _} = Workline.qa_verdict(led, "pass", "nolan", "=== after: R\n HOME", opts)
    assert {:ok, _} = Workline.owed_status(Repo.get!(Thread, thread.id), opts)
  end

  defp skips_qa(slug, paths, qa?) do
    {thread, opts} = at_review(slug, paths, qa: qa?)
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    assert Channel.thread_lead(thread.id) == "lonnrot"
    assert {:ok, %Thread{stage: "review", awaiting: nil}} = Workline.advance(Repo.get!(Thread, thread.id), opts)
    assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: thread.id})
  end

  test "a change with nothing user-visible skips QA" do
    skips_qa("server-only", ["server/lib/server/workline.ex"], true)
  end

  test "a bench with no qa seat skips QA" do
    skips_qa("no-qa-seat", ["office/tui/main.ts"], false)
  end

  test "QA is owed afresh each time it comes back to review" do
    {thread, opts} = at_review("again", ["office/tui/main.ts"])
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", opts)
    {:error, {:bounced, _}} = Workline.qa_verdict(Repo.get!(Thread, thread.id), "fail", "nolan", @broken_r, opts)

    {:ok, verifying} = Workline.advance(Repo.get!(Thread, thread.id), opts)
    {:ok, reviewing} = Workline.advance(verifying, opts)
    {:ok, _} = Workline.review_verdict(reviewing, "approve", "lonnrot", opts)
    assert {:error, {:artifact_missing, _}} = Workline.advance(Repo.get!(Thread, thread.id), opts)
  end

  test "a verdict other than pass or fail, or off the review stage, is refused" do
    {thread, opts} = at_review("refusals", ["office/tui/main.ts"])
    assert {:error, {:bad_verdict, "meh"}} = Workline.qa_verdict(thread, "meh", "nolan", "x", opts)

    built = Thread |> Repo.get!(thread.id) |> Map.put(:stage, "build")
    assert {:error, {:not_in_review, "build"}} = Workline.qa_verdict(built, "fail", "nolan", "x", opts)
  end
end
