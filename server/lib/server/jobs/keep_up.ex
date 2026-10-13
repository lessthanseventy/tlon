defmodule Server.Jobs.KeepUp do
  @moduledoc """
  Every few minutes, each project repo's landings that GitHub left behind main are rebased so their
  auto-merge can go (`Server.Workline.Publish.refresh_behind/2`), those that now conflict with main
  are closed and their worklines sent back to build (`Server.Workline.reland/2`) rather than left
  stranded with their threads closed, and those whose checks went red (so auto-merge never fires)
  are closed, reported to the workspace's sheriff and sent back the same way, and its main
  checkout is brought level with origin/main, fast-forward only (`follow_main/2`). A landing waiting
  on GitHub (`Server.Workline.waiting_on_github/0`) is done only when GitHub reads its PR as
  `MERGED`: then its thread closes, its ticket is done and its issues resolved (`Server.Workline.merged/2`).
  One GitHub closed unmerged, or holds `BLOCKED` with no check still running, is recorded as blocked
  (`Server.Workline.landing_blocked/2`), a `pr_blocked` Need.

  A `gh` read that fails is logged and acted on as nothing. A repo whose pass raises (gh missing
  from PATH, a git that won't run) leaves the other repos their pass, then fails the job with every
  such fault, so it reaches the operator as a failed job (`Server.Office.Needs`), not only a log line.

  A main that has drifted is never merged: it is one ticket (and one lobby post) in the workspace
  whose project owns the repo, or one keyed note for the operator when none does, updated in place
  and cleared only when main is level again. Whether the operator should also hear when the crew
  can't handle a drift (a live session committing to that main) is open.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 120]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    faults = Enum.flat_map(repos(), &keep_up/1) ++ landings() ++ requeue_stranded()

    if faults == [], do: :ok, else: {:error, Enum.join(faults, "; ")}
  end

  # one repo's fault (gh missing from PATH, a git that won't run) doesn't skip the others; the faults
  # fail the job after every repo had its pass, so they reach the operator as a failed job
  defp keep_up(repo) do
    read(repo, "behind PRs", Server.Workline.Publish.refresh_behind(repo))
    reland(repo)
    red_checks(repo)
    drifted(repo, Server.Workline.Publish.follow_main(repo))
    []
  rescue
    e -> fault("keep_up #{repo}: #{Exception.message(e)}")
  end

  defp fault(why) do
    require(Logger) && Logger.error(why)
    [why]
  end

  defp reland(repo) do
    for %{number: n, slug: slug} <- read(repo, "conflicting PRs", Server.Workline.Publish.conflicting(repo)),
        %Server.Thread{stage: "merged"} = t <- [Server.Repo.get_by(Server.Thread, slug: slug)] do
      why = "its PR ##{n} conflicts with main"

      with :ok <- Server.Workline.Publish.close(repo, n, "#{why}; the workline is back at build to rebase it"),
           do: Server.Workline.reland(t, why)
    end
  end

  # a gh read that failed is said, and acted on as nothing: never a PR set read as empty in silence
  defp read(repo, what, {:error, why}) do
    require(Logger) && Logger.warning("keep_up #{repo}: #{what} unread — #{why}")
    []
  end

  defp read(_repo, _what, prs), do: prs

  @doc false
  # a landing is done when GitHub says its PR is MERGED, never at the local gate
  def landings(run \\ &System.cmd/3) do
    for %{thread: t, url: url} <- Server.Workline.waiting_on_github() do
      case Server.Workline.Publish.view(Server.Workline.Artifacts.Git.root(t), url, run) do
        {:ok, %{"state" => "MERGED"}} -> Server.Workline.merged(t, url)
        {:ok, %{"state" => "CLOSED"}} -> Server.Workline.landing_blocked(t, "its PR was closed on GitHub, unmerged")
        {:ok, %{"mergeStateStatus" => "BLOCKED"} = pr} -> blocked(t, pr)
        {:ok, _pr} -> :ok
        {:error, why} -> require(Logger) && Logger.warning("keep_up #{t.slug}: #{url} unread — #{why}")
      end
    end

    []
  rescue
    e -> fault("keep_up landings: #{Exception.message(e)}")
  end

  # BLOCKED while its checks run is GitHub waiting on them; with none running, a rule holds it
  defp blocked(t, pr) do
    if !Server.Workline.Publish.checks_running?(pr),
      do: Server.Workline.landing_blocked(t, "GitHub reports it BLOCKED with no check running: a rule holds it")
  end

  # approved worklines whose Land job Lifeline rescued or discarded wait at review with nothing queued
  defp requeue_stranded do
    Server.Workline.requeue_stranded()
    []
  rescue
    e -> fault("keep_up requeue_stranded: #{Exception.message(e)}")
  end

  @doc false
  def red_checks(repo, run \\ &System.cmd/3) do
    for %{number: n, slug: slug} <- read(repo, "red PRs", Server.Workline.Publish.failing(repo, run)),
        %Server.Thread{stage: "merged"} = t <- [Server.Repo.get_by(Server.Thread, slug: slug)] do
      why = "its PR ##{n}'s checks went red"

      with :ok <- Server.Workline.Publish.close(repo, n, "#{why}; the workline is back at build to fix it", run) do
        Server.Sheriff.report(t, "#{why}, so GitHub will never merge it; the workline is back at build")
        Server.Workline.reland(t, why, "#{why}. Fix work/#{t.slug} until its checks pass, test")
      end
    end
  end

  @doc false
  # One note per repo. A repo a project owns goes to that project's workspace: its lobby hears it once
  # and one ticket carries the count for the crew to land; the operator is not asked. A repo no
  # project owns has no crew to hand it to, so it stays a single keyed note for the operator.
  def drifted(repo, {:diverged, n}) do
    title = "land local main's #{n} commit#{if n == 1, do: "", else: "s"}"

    case owner(repo) do
      nil ->
        Server.Rollout.note(
          {:drift, repo},
          "#{repo}: local main has #{n} commit(s) origin/main doesn't — move them to a branch, then reset main to origin/main"
        )

      ws ->
        route(ws, repo, title, n)
    end
  end

  def drifted(repo, :forwarded) do
    Server.Rollout.clear({:drift, repo})

    with ws when not is_nil(ws) <- owner(repo), %Server.Ticket{} = t <- open_ticket(ws, repo) do
      Server.Tickets.update(t, %{status: "done"})
    end

    :ok
  end

  # an error or a skipped check says nothing about drift: leave the note and ticket as they are
  def drifted(_repo, _other), do: :ok

  # An owned repo's drift must reach someone: with no lobby to post on, or a ticket write that failed,
  # it falls back to the keyed operator note rather than vanishing.
  defp route(ws, repo, title, n) do
    body =
      "#{repo}: local main has #{n} commit(s) origin/main doesn't. Review them and land them as a workline; never reset main under a live session."

    lobby = Server.Channel.machine_thread(ws)

    posted =
      case open_ticket(ws, repo) do
        nil ->
          with {:ok, _} <- Server.Tickets.file(%{workspace_id: ws, title: title, body: body, labels: [label(repo)]}),
               %Server.Thread{id: tid} <- lobby,
               {:ok, _} <- Server.Channel.post(%{thread_id: tid, author: "tlon", body: "⚠ " <> title <> " — " <> body}),
               do: :ok

        t ->
          with {:ok, _} <- Server.Tickets.update(t, %{title: title, body: body}),
               %Server.Thread{} <- lobby,
               do: :ok
      end

    if posted != :ok, do: Server.Rollout.note({:drift, repo}, body)
    :ok
  end

  defp label(repo), do: "drift:" <> repo

  defp open_ticket(ws, repo), do: Enum.find(Server.Tickets.open_in_workspace(ws), &(label(repo) in (&1.labels || [])))

  defp owner(repo) do
    Enum.find_value(Server.Repo.all(Server.Project), fn p ->
      if Server.Projects.primary_repo_path(p) == {:ok, repo}, do: p.workspace_id
    end)
  end

  defp repos do
    Server.Project
    |> Server.Repo.all()
    |> Enum.flat_map(fn p ->
      case Server.Projects.primary_repo_path(p) do
        {:ok, path} -> [path]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end
end
