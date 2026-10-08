defmodule Server.Jobs.KeepUp do
  @moduledoc """
  Every few minutes, each project repo's landings that GitHub left behind main are rebased so their
  auto-merge can go (`Server.Workline.Publish.refresh_behind/2`), those that now conflict with main
  are closed and their worklines sent back to build (`Server.Workline.reland/2`) rather than left
  stranded with their threads closed, and its main checkout is brought
  level with origin/main, fast-forward only (`follow_main/2`); one that has drifted is a note for
  the operator, never a merge.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 120]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for repo <- repos() do
      Server.Workline.Publish.refresh_behind(repo)
      reland(repo)
      drifted(repo, Server.Workline.Publish.follow_main(repo))
    end

    :ok
  end

  defp reland(repo) do
    for %{number: n, slug: slug} <- Server.Workline.Publish.conflicting(repo),
        %Server.Thread{stage: "merged"} = t <- [Server.Repo.get_by(Server.Thread, slug: slug)] do
      why = "its PR ##{n} conflicts with main"

      with :ok <- Server.Workline.Publish.close(repo, n, "#{why}; the workline is back at build to rebase it"),
           do: Server.Workline.reland(t, why)
    end
  end

  defp drifted(repo, {:diverged, n}) do
    text =
      "#{repo}: local main has #{n} commit(s) origin/main doesn't — move them to a branch, then reset main to origin/main"

    if !Enum.any?(Server.Rollout.pending(), &(&1.text == text)), do: GenServer.cast(Server.Rollout, {:note, text})
  end

  defp drifted(_repo, _result), do: :ok

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
