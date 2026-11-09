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
  alias Server.Workline.Grade
  alias Server.Workline.Scribe
  alias Server.Workline.Stage

  require Logger

  # What Andrew sees: the office, and the operator API it reads (the office snapshot rides on it).
  @user_visible ~w(office/ server/lib/server/mcp/operator_api.ex server/lib/server/office)

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
      Server.BranchReview.builders(root, "#{main_ref(root) || "main"}..work/#{slug}", [
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
         auto_land?(thread, checker, opts),
       do: Stage.queue(thread, auto_land_note(thread, opts), "auto_land_risk"),
       else: {:ok, thread}
  end

  @doc """
  The limits the newest risk grade since the workline entered review hit (`Grade.limits/1`): `[]`
  when none, ungraded, or the grader failed.
  """
  def grade_limits(%Thread{} = thread) do
    case grade(thread) do
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
    case since_review(thread, "workline:#{thread.slug}:review") do
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

        case qa_owed(thread, opts) do
          nil -> park_approved(thread, opts)
          {seat, paths} -> {:ok, to_qa(thread, seat, paths)}
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
        if qa_owed(fresh, opts) == nil, do: park_approved(fresh, opts), else: {:ok, fresh}

      fresh ->
        {:ok, fresh}
    end
  end

  defp park_refusal({:artifact_missing, why}), do: "owed artifact missing: #{why}"
  defp park_refusal({:queue, why}), do: "the merge queue refused it: #{inspect(why)}"
  defp park_refusal(why), do: inspect(why)

  defp follow_up_title(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.trim()

  # A standing approval: the operator's `auto_land_risk` — a reviewed-and-approved workline whose
  # risk grade has no axis over it (and no limit hit, no decision left open) lands without them,
  # through the same gated queue. Off unless set; a test hands the threshold outright.
  # A builder with a good enough record has earned a step more of it (`Server.Trust`).
  def auto_land?(thread, checker, opts) do
    max = Keyword.get_lazy(opts, :auto_land_risk, fn -> if checker == Git, do: auto_land_risk() end)

    is_integer(max) and review_approved?(thread) and
      Grade.allows?(grade(thread), elem(Server.Trust.allowance(thread, max), 0)) and
      qa_cleared(thread, opts) == :ok
  end

  def auto_land_note(thread, opts) do
    {max, earned} = Server.Trust.allowance(thread, Keyword.get_lazy(opts, :auto_land_risk, &auto_land_risk/0))

    by =
      if earned,
        do:
          ": one over your setting, earned by #{earned.name}#{if earned.model, do: " on #{earned.model}"}, who landed #{earned.first_time} of their last #{earned.led} builds first time",
        else: ""

    "auto-approved by your standing approval (reviewed; #{Grade.line(grade(thread))}, none over #{max}#{by})"
  end

  # the newest grade since the workline last entered review: nil if none, or the grader failed
  def grade(thread) do
    case since_review(thread, "workline:#{thread.slug}:grade") do
      %{kind: "check_passed", detail: grade} -> grade
      _ -> nil
    end
  end

  # the newest event of `correlation` since the workline last entered review
  def since_review(thread, correlation) do
    entered =
      Repo.one(
        from e in Server.Event,
          where:
            e.thread_id == ^thread.id and e.kind == "stage_advanced" and
              fragment("(?::jsonb ->> 'to') = 'review'", e.detail),
          select: max(e.id)
      ) || 0

    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.correlation == ^correlation and e.id > ^entered,
        order_by: [desc: e.id],
        limit: 1
    )
  end

  # at review, a change Andrew would see waits on a QA pass since it last entered review — where the
  # bench seats a qa; a bench without one lands it as before
  def qa_cleared(thread, opts) do
    case qa_owed(thread, opts) do
      nil ->
        :ok

      {seat, _paths} ->
        if Server.Channel.thread_lead(thread.id) == seat.name,
          do: {:error, {:artifact_missing, "QA is yours: " <> qa_playbook(thread)}},
          else:
            {:error,
             {:artifact_missing,
              "QA hasn't passed this user-visible change: #{seat.name} drives it against a scratch release and files what it saw with submit_qa"}}
    end
  end

  def qa_owed(%Thread{stage: "review", workspace_id: ws} = thread, opts) when not is_nil(ws) do
    with %Server.Coworker{} = seat <- qa_seat(thread),
         [_ | _] = paths <- Enum.filter(changed_paths(thread, opts), &String.starts_with?(&1, @user_visible)),
         false <- match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:qa")) do
      {seat, paths}
    else
      _ -> nil
    end
  end

  def qa_owed(_thread, _opts), do: nil

  def to_qa(thread, seat, paths) do
    handed = Workline.hand_to(thread, "qa", seat.name)

    Workline.post_brief(
      handed,
      "🎭 QA: the review approved a change Andrew will see (#{Enum.join(Enum.take(paths, 5), ", ")}). " <>
        String.capitalize(qa_playbook(thread))
    )

    handed
  end

  # the review approved the code it read (its verdict's `sha`): code committed after it goes back
  # to build like any other change, through verify and a review of what changed
  def reviewed_current(%Thread{stage: "review"} = thread) do
    with %{detail: %{"sha" => seen}} when is_binary(seen) <- since_review(thread, "workline:#{thread.slug}:review"),
         now when is_binary(now) <- Workline.branch_head(thread),
         {:changed, how} <- compare_code(thread, seen, now) do
      why =
        if how == :conflicts,
          do: "work/#{thread.slug} was rebased onto main with conflicts resolved after its review",
          else: "work/#{thread.slug} has code committed after its review"

      Workline.bounce(
        thread,
        why,
        "#{why} (reviewed at #{String.slice(seen, 0, 7)}, now #{String.slice(now, 0, 7)}): it comes back through verify and a review of what changed"
      )
    else
      _ -> :ok
    end
  end

  def reviewed_current(_thread), do: :ok

  def main_ref(root) do
    Enum.find(
      ["origin/main", "main"],
      &match?({_, 0}, Server.Git.cmd(root, ["rev-parse", "--verify", "--quiet", &1]))
    )
  end

  # The branch's own change at `head` against what was judged at `sha`, not their trees: its commits
  # main doesn't already have (`git cherry`, so a commit main took on its own drops out), each by the
  # patch-id of its code (work/<slug>/ left out: the server commits review.md after a verdict). A
  # rebase onto a newer main (the merge queue keeps its rebase across a cut-off gate) is `:same`; the
  # same commits with other patches are `{:changed, :conflicts}`, a resolved rebase; anything else
  # `{:changed, :code}`. A git error is `{:changed, :unreadable}`, and logged.
  def compare_code(_thread, sha, sha), do: :same

  def compare_code(thread, sha, head) do
    root = Git.root(thread)

    with base when is_binary(base) <- main_ref(root),
         {:ok, seen} <- own_patches(root, base, sha, thread.slug),
         {:ok, now} <- own_patches(root, base, head, thread.slug) do
      patches_compared(seen, now, fn -> same_tree?(root, sha, head, thread.slug) end)
    else
      why ->
        require(Logger) && Logger.warning("workline #{thread.slug}: can't compare #{sha} with #{head}: #{inspect(why)}")
        {:changed, :unreadable}
    end
  end

  # `{subject, patch-id}` lists: the same patches are the same change; the same commits with other
  # patches, a rebase whose conflicts were resolved. No commits of its own on either side (its code
  # is on main already): `same_tree?` decides.
  defp patches_compared([], [], same_tree?), do: if(same_tree?.(), do: :same, else: {:changed, :code})

  defp patches_compared(seen, now, _same_tree?) do
    cond do
      Enum.map(seen, &elem(&1, 1)) == Enum.map(now, &elem(&1, 1)) -> :same
      Enum.map(seen, &elem(&1, 0)) == Enum.map(now, &elem(&1, 0)) -> {:changed, :conflicts}
      true -> {:changed, :code}
    end
  end

  defp auto_land_risk, do: Server.OperatorConfig.setting("auto_land_risk")

  defp review_approved?(thread),
    do: match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:review"))

  defp qa_playbook(thread) do
    """
    drive the changed path as Andrew would, against a scratch release of work/#{thread.slug}: \
    `start_smoke(thread_id: #{thread.id})` has the service build it on its own port and db, smoke it and keep it up \
    (it posts the url here); drive it with `drive_smoke(keys, thread_id: #{thread.id})`, the steps of `office:drive`; \
    `stop_smoke` when done. Your own Bash can run neither: it has no Postgres socket and a network of its own. \
    Never :4040, the live service. Then submit_qa with thread_id: #{thread.id}: pass, or fail with the \
    finding — what you pressed and the screen text you saw.\
    """
  end

  defp changed_paths(thread, opts) do
    Keyword.get_lazy(opts, :paths, fn ->
      if Keyword.get(opts, :artifacts, Git) == Git, do: Git.changed_paths(thread), else: []
    end)
  end

  # the thread's lead when it is the qa already, else a free one, else any
  defp qa_seat(thread) do
    seats = thread.workspace_id |> Server.Workspaces.bench() |> Enum.filter(&(&1.archetype == "qa"))
    current = Server.Channel.thread_lead(thread.id)

    Enum.find(seats, &(&1.name == current)) || Enum.find(seats, &(not Workline.leading_another?(&1, thread))) ||
      List.first(seats)
  end

  # no commits of its own on either side (its code is on main already): the trees decide
  defp same_tree?(root, sha, head, slug),
    do: match?({_, 0}, Server.Git.cmd(root, ["diff", "--quiet", sha, head, "--", ".", ":!work/#{slug}"]))

  # `{subject, patch-id}` of each of `ref`'s commits main doesn't have that touches code, oldest first
  defp own_patches(root, base, ref, slug) do
    case Server.Git.cmd(root, ["cherry", base, ref]) do
      {out, 0} ->
        commits = for "+ " <> c <- String.split(out, "\n", trim: true), do: c
        patches_of(root, slug, commits)

      {out, code} ->
        {:error, {code, String.slice(out, 0, 200)}}
    end
  end

  defp patches_of(_root, _slug, []), do: {:ok, []}

  defp patches_of(root, slug, commits) do
    # pipefail: a git failure is the pipeline's, not hidden behind patch-id's exit
    script = ~s(git -C "$1" show --format='commit %H' "${@:3}" -- . ":!work/$2" | git patch-id --stable)

    with {ids, 0} <-
           Server.Cmd.run("bash", ["-o", "pipefail", "-c", script, "bash", root, slug | commits],
             stderr_to_stdout: true
           ),
         {subjects, 0} <-
           Server.Git.cmd(root, ["show", "-s", "--format=%H%x09%s" | commits]) do
      id_of =
        Map.new(String.split(ids, "\n", trim: true), &(&1 |> String.split(" ") |> Enum.reverse() |> List.to_tuple()))

      subject_of =
        Map.new(String.split(subjects, "\n", trim: true), &(&1 |> String.split("\t", parts: 2) |> List.to_tuple()))

      {:ok, for(c <- commits, id = id_of[c], do: {subject_of[c], id})}
    else
      {out, code} -> {:error, {code, String.slice(out, 0, 200)}}
    end
  end
end
