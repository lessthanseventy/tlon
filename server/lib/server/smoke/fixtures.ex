defmodule Server.Smoke.Fixtures do
  @moduledoc """
  The closed catalog of seed sets a smoke can be started with (`start_smoke`'s `fixtures`). Each runs
  inside the smoke node, through the server's own contexts, so seeded rows pass the live
  validations. It ships with the candidate build: the catalog is the review surface for what a smoke
  can be made to believe. Refuses any database that is not a scratch `tlon_smoke_*` one.
  """
  import Ecto.Query, only: [from: 2]
  import Kernel, except: [apply: 2]

  @doc "Run the fixture `name` on this node's database (`rpc`'d by `scripts/release-smoke.sh`)."
  @spec apply(String.t()) :: :ok
  def apply(name), do: apply(name, Server.Repo.config()[:database])

  @doc false
  def apply(name, database) do
    if !(is_binary(database) and String.starts_with?(database, "tlon_smoke_")),
      do: raise(ArgumentError, "fixtures run only on a tlon_smoke_* database, not #{inspect(database)}")

    case Map.fetch(catalog(), name) do
      {:ok, seed} -> seed.()
      :error -> raise ArgumentError, "unknown fixture #{inspect(name)}: #{Enum.join(names(), ", ")}"
    end
  end

  @doc "The catalog's names."
  @spec names() :: [String.t()]
  def names, do: catalog() |> Map.keys() |> Enum.sort()

  defp catalog, do: %{"tool_denied_need" => &tool_denied_need/0, "ticket_tree" => &ticket_tree/0}

  # Needs.tool_denied: an open thread refused a tool twice since it last moved, nobody on duty
  defp tool_denied_need do
    {:ok, t} = Server.Channel.open_thread(%{title: "fixture: a refused tool"})
    # denials count only when strictly after the thread's birth, and both are stamped to the second
    born = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    Server.Repo.update_all(from(x in Server.Thread, where: x.id == ^t.id), set: [created_at: born])

    for _ <- 1..2 do
      {:ok, _} =
        Server.Dossier.record_event(%{
          thread_id: t.id,
          kind: "tool_denied",
          correlation: "tool_denied:#{t.id}",
          detail: %{"agent" => "fixture", "tool" => "Bash", "summary" => "Bash · echo hi", "reason" => "fixture"}
        })
    end

    :ok
  end

  # The TICKETS column's tree: an initiative holding an epic, a free child, a child started into a thread
  # (so it shows as in flight), and a loose ticket outside any group.
  defp ticket_tree do
    {:ok, %{id: ws}} = Server.Bootstrap.ensure()
    {:ok, initiative} = Server.Tickets.file(%{workspace_id: ws, title: "fixture: an initiative", kind: "initiative"})

    {:ok, epic} =
      Server.Tickets.file(%{workspace_id: ws, title: "fixture: an epic", kind: "epic", epic_id: initiative.id})

    {:ok, _free} = Server.Tickets.file(%{workspace_id: ws, title: "fixture: a free child", epic_id: epic.id})
    {:ok, in_flight} = Server.Tickets.file(%{workspace_id: ws, title: "fixture: a child in flight", epic_id: epic.id})
    {:ok, thread} = Server.Channel.open_thread(%{title: "fixture: the child in flight"})
    {:ok, _} = Server.Tickets.promote(in_flight, thread.id)
    {:ok, _} = Server.Tickets.file(%{workspace_id: ws, title: "fixture: a loose ticket"})
    :ok
  end
end
