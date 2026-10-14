defmodule Server.Jobs.Diary do
  @moduledoc """
  Weekly (Monday, `config/config.exs`), each builder seat's week is written to its soul's Diary
  (`Server.Diary.write/3`). A seat whose newest diary line is under six days old is skipped, so a
  retry or a restart never writes the week twice. A seat with no soul file is skipped, never created.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 3600]

  alias Server.{Diary, Soul, Workspaces}

  @week 7
  @spacing 6

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    since = DateTime.new!(Date.add(today, -@week), ~T[00:00:00], "Etc/UTC")

    for %{id: workspace_id} <- Workspaces.all(),
        {seat, items} <- Diary.history(workspace_id, since),
        due?(seat, today) do
      Diary.write(seat, items, today)
    end

    :ok
  end

  defp due?(seat, today) do
    with line when is_binary(line) <- seat |> Soul.diary() |> List.last(),
         [_, date] <- Regex.run(~r/^- (\d{4}-\d{2}-\d{2}):/, line),
         {:ok, written} <- Date.from_iso8601(date) do
      Date.diff(today, written) >= @spacing
    else
      _ -> true
    end
  end
end
