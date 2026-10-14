defmodule Server.Jobs.Diary do
  @moduledoc """
  Weekly (Monday, `config/config.exs`), each builder seat's week is written to its soul's Diary
  (`Server.Diary.write/3`). A seat whose newest diary line is under six days old is skipped, so a
  retry or a restart never writes the week twice. A seat with no soul file is skipped, never created.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 3600]

  alias Server.{Diary, Workspaces}

  @week 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    since = DateTime.new!(Date.add(today, -@week), ~T[00:00:00], "Etc/UTC")

    for %{id: workspace_id} <- Workspaces.all(),
        {seat, items} <- Diary.history(workspace_id, since),
        Diary.due?(seat, today) do
      Diary.write(seat, items, today)
    end

    :ok
  end
end
