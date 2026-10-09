defmodule Server.Jobs.KeepUp do
  @moduledoc """
  Every few minutes, each project repo's landings that GitHub left behind main are rebased so their
  auto-merge can go (`Server.Workline.Publish.refresh_behind/2`), those that now conflict with main
  are closed and their worklines sent back to build (`Server.Workline.reland/2`) rather than left
  stranded with their threads closed, and its main checkout is brought level with origin/main,
  fast-forward only (`follow_main/2`).

  A main that has drifted is never merged: it is one ticket (and one lobby post) in the workspace
  whose project owns the repo, or one keyed note for the operator when none does, updated in place
  and cleared only when main is level again. Whether the operator should also hear when the crew
  can't handle a drift (a live session committing to that main) is open.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 120]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for repo <- repos(), do: keep_up(repo)

    :ok
  end

  # one repo's fault (gh missing from PATH, a git that won't run) doesn't skip the others
  defp keep_up(repo) do
    Server.Workline.Publish.refresh_behind(repo)
    reland(repo)
    drifted(repo, Server.Workline.Publish.follow_main(repo))
  rescue
    e -> require(Logger) && Logger.error("keep_up #{repo}: #{Exception.message(e)}")
  end

  defp reland(repo) do
    for %{number: n, slug: slug} <- Server.Workline.Publish.conflicting(repo),
        %Server.Thread{stage: "merged"} = t <- [Server.Repo.get_by(Server.Thread, slug: slug)] do
      why = "its PR ##{n} conflicts with main"

      with :ok <- Server.Workline.Publish.close(repo, n, "#{why}; the workline is back at build to rebase it"),
           do: Server.Workline.reland(t, why)
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
