defmodule Server.Smoke.Fixtures do
  @moduledoc """
  The closed catalog of seed sets a smoke can be started with (`start_smoke`'s `fixtures`). Each runs
  inside the smoke node, through the server's own contexts, so seeded rows pass the live
  validations. It ships with the candidate build: the catalog is the review surface for what a smoke
  can be made to believe. Refuses any database that is not a scratch `tlon_smoke_*` one.
  """
  import Ecto.Query, only: [from: 2]
  import Kernel, except: [apply: 2]

  @fixture ~r/\A([a-z][a-z0-9_]*)(?::([a-z][a-z0-9_]*=[A-Za-z0-9_.-]+(?:,[a-z][a-z0-9_]*=[A-Za-z0-9_.-]+)*))?\z/

  @doc """
  Run the fixture `spec` on this node's database (`rpc`'d by `scripts/release-smoke.sh`). A spec is a
  name, and after a colon its params: `quota_refused_need:provider=ollama-cloud`. It has no spaces, so
  it travels as one word through `TLON_SMOKE_FIXTURES`.
  """
  @spec apply(String.t()) :: :ok
  def apply(spec), do: apply(spec, Server.Repo.config()[:database])

  @doc false
  def apply(spec, database) do
    if !(is_binary(database) and String.starts_with?(database, "tlon_smoke_")),
      do: raise(ArgumentError, "fixtures run only on a tlon_smoke_* database, not #{inspect(database)}")

    {name, params} = parse(spec)

    case Map.fetch(catalog(), name) do
      {:ok, {defaults, seed}} ->
        case Map.keys(params) -- Map.keys(defaults) do
          [] ->
            seed.(Map.merge(defaults, params))

          extra ->
            raise ArgumentError,
                  "unknown param #{Enum.join(extra, ", ")} for #{name}: #{Enum.join(Map.keys(defaults), ", ")}"
        end

      :error ->
        raise ArgumentError, "unknown fixture #{inspect(name)}: #{Enum.join(names(), ", ")}"
    end
  end

  @doc "A fixture spec as `{name, %{param => value}}`; raises on one that is not `name` or `name:k=v,k=v`."
  @spec parse(String.t()) :: {String.t(), %{String.t() => String.t()}}
  def parse(spec) do
    case is_binary(spec) && Regex.run(@fixture, spec) do
      [_, name] -> {name, %{}}
      [_, name, params] -> {name, params |> String.split(",") |> Map.new(&List.to_tuple(String.split(&1, "=")))}
      _ -> raise ArgumentError, "not a fixture: #{inspect(spec)} (name or name:key=value,key=value)"
    end
  end

  @doc "The catalog's names."
  @spec names() :: [String.t()]
  def names, do: catalog() |> Map.keys() |> Enum.sort()

  # name => {param defaults, seeder}: a param not in the defaults is refused
  defp catalog do
    %{
      "tool_denied_need" => {%{}, &tool_denied_need/1},
      "ticket_tree" => {%{}, &ticket_tree/1},
      "quota_refused_need" => {%{"provider" => "ollama-cloud"}, &quota_refused_need/1}
    }
  end

  # Needs.quota: a non-anthropic provider's one-shot refused with its plan's 429 (a seat on it is the
  # precondition, so the first coworker of the default workspace is moved onto the provider)
  defp quota_refused_need(%{"provider" => provider}) do
    {:ok, %{id: ws}} = Server.Bootstrap.ensure()
    [seat | _] = Server.Workspaces.bench_all(ws)
    agent = Server.Staff.agent_by_name(seat.name)
    {:ok, _} = Server.Workspaces.retarget(ws, agent.id, %{model: "#{provider}/glm-5.2"})

    :ok =
      Server.Shifts.refused(
        provider,
        "API Error: Request rejected (429) · you (fixture) have reached your weekly usage limit, upgrade for higher limits: https://ollama.com/upgrade (ref: 0000)"
      )
  end

  # Needs.tool_denied: an open thread refused a tool twice since it last moved, nobody on duty
  defp tool_denied_need(_params) do
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
  defp ticket_tree(_params) do
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
