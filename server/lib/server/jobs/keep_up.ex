defmodule Server.Jobs.KeepUp do
  @moduledoc """
  Every few minutes, each project repo's landings that GitHub left behind main are rebased so their
  auto-merge can go (`Server.Workline.Publish.refresh_behind/2`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 120]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for repo <- repos(), do: Server.Workline.Publish.refresh_behind(repo)
    :ok
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
