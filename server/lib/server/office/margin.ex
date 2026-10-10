defmodule Server.Office.Margin do
  @moduledoc """
  Uqbar's margin notes (docs/plans/2026-10-08-uqbar-design.md §4): the `margin`-kind messages on a
  workspace's root thread, which the office draws in the room's margins. Read-only: they are
  written by the `margin_note` tool and wake nobody.
  """
  import Ecto.Query

  alias Server.{Channel, Message, Repo}

  @keep 12

  @doc "The workspace's margin notes, newest first: `[%{id, author, body, at}]` (`at` unix seconds)."
  @spec notes(integer()) :: [map()]
  def notes(workspace_id) do
    case Channel.machine_thread(workspace_id) do
      nil ->
        []

      %{id: root_id} ->
        from(m in Message, where: m.thread_id == ^root_id and m.kind == "margin", order_by: [desc: m.id], limit: @keep)
        |> Repo.all()
        |> Enum.map(&%{id: &1.id, author: &1.author, body: &1.body, at: DateTime.to_unix(&1.created_at)})
    end
  end
end
