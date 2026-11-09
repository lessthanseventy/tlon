defmodule Server.Workline.Review do
  @moduledoc """
  The reviewer's ONE door (worklines slice 3). The reviewer profile is structurally
  write-fenced (@reviewer_permissions denies write/edit + bash redirects), so review.md
  cannot be hand-written — `submit/3` is the single sanctioned path: server writes
  `work/<slug>/review.md` in the workline root and commits it. The fence stays airtight;
  a hook, not an advisory.

  Also the verdicts on a review: the reviewer's and the qa seat's, who may not review their own
  build, the risk grade's reach on a gate, and the follow-ups a verdict hands on.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Artifacts.Git
  alias Server.Workline.Scribe

  @doc """
  Write + commit the review verdict. `{:ok, rel_path}`, `{:error, {:not_in_review, stage}}`
  outside the review stage, or `{:error, reason}` on a git fault. Identical resubmission is
  `{:ok, _}` — the artifact is already committed, which is the point.
  """
  def submit(%Thread{stage: "review", slug: slug} = thread, body, author) when is_binary(body) do
    model = Server.Profiles.model_label(thread.workspace_id, author)

    trailers =
      Enum.join(
        ["Tlon-Thread: #{thread.id}", "Tlon-Author: #{author}" | if(model, do: ["Tlon-Model: #{model}"], else: [])],
        "\n"
      )

    Scribe.commit(
      thread,
      "review.md",
      body,
      "workline #{slug}: review verdict (submit_review by #{author})\n\n#{trailers}"
    )
  end

  def submit(%Thread{stage: stage}, _body, _author), do: {:error, {:not_in_review, stage}}

  @doc """
  The reviewer's verdict on its submitted review — `"approve"` or `"request_changes"` — recorded as
  evidence (`workline:<slug>:review`). Changes requested send it straight back to build, its builder
  told to read review.md: a review asking for changes never reaches the operator's gate. An approval
  is what a standing approval (`auto_land_risk` in the settings file) needs to land without them,
  and asks for the risk grade it is decided on (`Server.Jobs.Grade`); a change that owes QA is
  handed to the qa seat. An approval of a commit already approved this round is that same
  approval, nothing recorded: a client retries a call whose connection dropped. A thread parked or
  handed to QA is `{:ok, thread}`; one the first approval left at review unparked (its park refused)
  is parked now, the same `advance/2` and the same refusal if it still fails (`park_approved/2`),
  never `{:ok, thread}` for a thread nothing queued. The verdict ends the reviewer's session (a
  review is a throwaway session, briefed fresh each round) last, from `Server.Jobs.EndReview`, once
  the thread has moved and its `follow_ups:` (non-blocking findings) are posted for the lead it hands
  to (`follow_ups/4`): the window closing cancels the request on the server. A verdict by the
  agent that built the branch is refused, `{:error, {:self_review, why}}` (`self_review/2`).
  `opts` as `advance/2`'s, and `paths:` the changed paths (tests).
  """
  def review_verdict(thread, verdict, author, opts \\ [])

  def review_verdict(%Thread{stage: "review"} = thread, verdict, author, opts)
      when verdict in ~w(approve request_changes) do
    sha = Keyword.get_lazy(opts, :branch_head, fn -> Workline.branch_head(thread) end)

    cond do
      why = self_review(thread, author) -> {:error, {:self_review, why}}
      verdict == "approve" and approved_at?(thread, sha) -> finish_approval(thread, opts)
      true -> record_verdict(thread, verdict, author, sha, opts)
    end
  end

  def review_verdict(%Thread{stage: "review"}, verdict, _author, _opts), do: {:error, {:bad_verdict, verdict}}

  def review_verdict(%Thread{stage: stage}, _verdict, _author, _opts), do: {:error, {:not_in_review, stage}}

  @doc """
  Why `author` may not review `thread`'s branch — it built it: the git author or `Tlon-Author:` of a
  commit on `work/<slug>` past main, its own review.md aside (`Server.BranchReview.builders/3`) — or
  nil when it may.
  """
  def self_review(%Thread{slug: slug} = thread, author) do
    root = Git.root(thread)

    builders =
      Server.BranchReview.builders(root, "#{Workline.main_ref(root) || "main"}..work/#{slug}", [
        "work/#{slug}/review.md"
      ])

    if Server.BranchReview.built?(author, builders),
      do: "#{author} authored a commit on work/#{slug}: its review is someone else's, never the builder's"
  end

  @doc """
  The qa seat's verdict on a reviewed change it drove (`submit_qa`): `"pass"` or `"fail"`, its report
  (what it pressed and the screen text it saw) recorded as evidence (`workline:<slug>:qa`). A fail
  sends it back to build with the finding, as a review requesting changes does; a pass advances it
  to the merge gate. Its `follow_ups:` are posted once it has moved, for the lead it hands to
  (`follow_ups/4`). `opts` as `advance/2`'s, plus `session_id:`, the QA seat's connection, stamped
  on the `qa by` check; the `cmd` string itself is what `Diary.verdict/1` parses.
  """
  def qa_verdict(thread, verdict, author, report, opts \\ [])

  def qa_verdict(%Thread{stage: "review"} = thread, verdict, author, report, opts) when verdict in ~w(pass fail) do
    {:ok, _} =
      Dossier.record_check(
        %{
          thread_id: thread.id,
          cmd: "qa by #{author}",
          exit: if(verdict == "pass", do: 0, else: 1),
          tail: report,
          correlation: "workline:#{thread.slug}:qa"
        },
        session_id: opts[:session_id]
      )

    by = Server.Authorship.label(author, opts[:session_id])

    outcome =
      if verdict == "fail" do
        Workline.bounce(
          thread,
          "QA found a problem",
          "QA (#{by}) drove it and found:\n\n#{report}\n\nFix it test-first",
          author
        )
      else
        Workline.post_brief(thread, "✓ QA passed (#{by}):\n\n#{report}")
        Workline.advance(Repo.get!(Thread, thread.id), opts)
      end

    {:ok, _} = follow_ups(thread, author, Keyword.get(opts, :follow_ups, []), :qa)
    outcome
  end

  def qa_verdict(%Thread{stage: "review"}, verdict, _author, _report, _opts), do: {:error, {:bad_verdict, verdict}}
  def qa_verdict(%Thread{stage: stage}, _verdict, _author, _report, _opts), do: {:error, {:not_in_review, stage}}

  @doc """
  A risk grade just recorded for `thread` (`Server.Jobs.Grade`): a gate parked on the operator
  that the grade now lets land under the standing approval joins the merge queue; anything else
  is left as it is. `{:ok, thread}`. `opts` as `advance/2`'s.
  """
  def graded(%Thread{} = thread, opts \\ []) do
    thread = Repo.get!(Thread, thread.id)
    checker = Keyword.get(opts, :artifacts, Git)

    if thread.stage == "review" and thread.awaiting == Workline.operator() and
         Workline.auto_land?(thread, checker, opts),
       do: Workline.queue(thread, Workline.auto_land_note(thread, opts), "auto_land_risk"),
       else: {:ok, thread}
  end

  @doc """
  The limits the newest risk grade since the workline entered review hit (`Grade.limits/1`): `[]`
  when none, ungraded, or the grader failed.
  """
  def grade_limits(%Thread{} = thread) do
    case Workline.grade(thread) do
      %{"limits" => [_ | _] = limits} -> limits
      _ -> []
    end
  end

  @doc """
  Whether the newest risk grade hit a limit: such a gate is the operator's alone. An ungraded
  workline, or a failed grade, is not limit-hit.
  """
  def limit_hit?(%Thread{} = thread), do: grade_limits(thread) != []

  @doc """
  A reviewer's or QA's non-blocking findings, posted on the workline for the lead its verdict hands
  to, so they are posted after the verdict moves it (`review_verdict/4`, `qa_verdict/5`): the builder
  on a bounce, the qa seat when QA is owed, and the operator when the thread is handed to their gate
  and its lead is still the author, whose session the verdict ended. One message, each text numbered
  (its first line the title, the rest the detail), blanks and repeated titles dropped
  (`follow_up_items/1`). None becomes a ticket here: the lead fixes what sits in the change's own
  lines before it lands, drops the rest, or defers one with `file_ticket`, which matches it against
  open tickets. Filing every finding grew the backlog faster than the office closed it. `{:ok,
  items}`, the items posted.
  """
  def follow_ups(%Thread{} = thread, author, items, door \\ :review) do
    items = follow_up_items(items)

    if items != [] do
      lead = Server.Channel.thread_lead(thread.id)
      to = if lead && lead != author, do: "@#{lead} ", else: "@#{Workline.operator()} "
      list = items |> Enum.with_index(1) |> Enum.map_join("\n", fn {text, i} -> "#{i}. #{text}" end)

      Workline.post_brief(
        thread,
        "#{to}follow-ups from #{author}'s #{door}:\n#{list}\n\n" <>
          "Fix any that sits in lines this change already touches before it lands. Drop the rest, or " <>
          "defer one someone would act on within a week with file_ticket (it is checked against open tickets)."
      )
    end

    {:ok, items}
  end

  @doc "The follow-ups `follow_ups/4` would post from `items`: trimmed, blanks and repeated titles dropped."
  def follow_up_items(items),
    do: items |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq_by(&follow_up_title/1)

  @doc """
  Lift the hold on a closing workline's follow-ups so intake routes them. One that closed without
  merging says so in each ticket's body, for the manager to check it still applies.
  """
  def release_follow_ups(%Thread{} = thread) do
    held = thread.id |> tied_follow_ups() |> Enum.filter(&("held" in &1.labels))

    note =
      if thread.stage == "landed",
        do: "",
        else: "\n\nIts workline (##{thread.id}) closed without merging: check this still applies."

    for t <- held,
        do: {:ok, _} = Server.Tickets.update(t, %{labels: t.labels -- ["held"], body: (t.body || "") <> note})

    if held != [],
      do: Workline.post_brief(thread, "↗ follow-ups to intake: " <> Enum.map_join(held, ", ", &"##{&1.id} #{&1.title}"))

    :ok
  end

  # how many times this workline's review has asked for changes (each verdict is recorded evidence)
  defp changes_requested(thread) do
    Repo.aggregate(
      from(e in Server.Event,
        where:
          e.thread_id == ^thread.id and e.kind == "check_failed" and e.correlation == ^"workline:#{thread.slug}:review"
      ),
      :count
    )
  end

  defp tied_follow_ups(thread_id) do
    from(t in Server.Ticket,
      join: tt in Server.TicketThread,
      on: tt.ticket_id == t.id,
      where: tt.thread_id == ^thread_id and tt.kind == "relates"
    )
    |> Repo.all()
    |> Enum.filter(&(is_list(&1.labels) and "follow-up" in &1.labels))
  end

  defp approved_at?(thread, sha) do
    case Workline.since_review(thread, "workline:#{thread.slug}:review") do
      %{kind: "check_passed", detail: detail} -> detail["sha"] == sha
      _ -> false
    end
  end

  defp record_verdict(thread, verdict, author, sha, opts) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "review verdict by #{author}",
        exit: if(verdict == "approve", do: 0, else: 1),
        tail: verdict,
        correlation: "workline:#{thread.slug}:review",
        sha: sha
      })

    outcome =
      if verdict == "request_changes" do
        bounced =
          Workline.bounce(
            thread,
            "the review requested changes",
            "the review requested changes: read work/#{thread.slug}/review.md, fix them test-first",
            author
          )

        if changes_requested(thread) >= 2,
          do: Workline.escalate(Repo.get!(Thread, thread.id), "the review asked for changes twice")

        bounced
      else
        Server.Jobs.enqueue(Server.Jobs.Grade.new(%{thread_id: thread.id}))

        case Workline.qa_owed(thread, opts) do
          nil -> park_approved(thread, opts)
          {seat, paths} -> {:ok, Workline.to_qa(thread, seat, paths)}
        end
      end

    {:ok, _} = follow_ups(thread, author, Keyword.get(opts, :follow_ups, []), :review)
    end_review(thread)
    outcome
  end

  # The reviewer's session ends last and off the request (`Server.Jobs.EndReview`): its window going
  # down cancels the request on the server, so a park or bounce still running in it dies mid-way.
  # A node without Oban ends it here, after the thread has moved.
  defp end_review(thread) do
    case Server.Jobs.enqueue(Server.Jobs.EndReview.new(%{thread_id: thread.id})) do
      {:ok, _} -> :ok
      {:error, _} -> Server.Staffing.end_review(thread)
    end
  end

  # The verdict ends the reviewer's session, so nobody is left to call advance_stage: the approval
  # parks the gate itself — on the operator, or straight into the queue under a standing
  # approval. A refused advance (review.md not committed, the queue down) would stall it, so it
  # is said on the thread and returned, never reported as parked; the verdict itself stands.
  defp park_approved(thread, opts) do
    case Workline.advance(Repo.get!(Thread, thread.id), opts) do
      {:awaiting, parked} ->
        {:ok, parked}

      {:ok, moved} ->
        {:ok, moved}

      {:error, why} ->
        why = park_refusal(why)

        Workline.post_brief(
          thread,
          "⚠ the approving verdict is recorded, but the workline is not parked at the gate: #{why}. " <>
            "It sits at review until its lead advances it (advance_stage)."
        )

        {:error, {:not_parked, why}}
    end
  end

  # The retry of an approval whose park was refused: the thread sits at review, awaiting nobody and
  # owing QA nothing, so the park is tried again. Parked or handed to QA, it is left as it is.
  defp finish_approval(thread, opts) do
    case Repo.get!(Thread, thread.id) do
      %Thread{stage: "review", awaiting: nil} = fresh ->
        if Workline.qa_owed(fresh, opts) == nil, do: park_approved(fresh, opts), else: {:ok, fresh}

      fresh ->
        {:ok, fresh}
    end
  end

  defp park_refusal({:artifact_missing, why}), do: "owed artifact missing: #{why}"
  defp park_refusal({:queue, why}), do: "the merge queue refused it: #{inspect(why)}"
  defp park_refusal(why), do: inspect(why)

  defp follow_up_title(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.trim()
end
