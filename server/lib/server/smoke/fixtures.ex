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
      "quota_refused_need" => {%{"provider" => "ollama-cloud"}, &quota_refused_need/1},
      "failed_job" => {%{}, &failed_job/1},
      "health_need" => {%{"what" => "disk"}, &health_need/1},
      "settled_need" => {%{}, &settled_need/1},
      "passed_up_need" => {%{}, &passed_up_need/1},
      "interrupted_schedule_run" => {%{}, &interrupted_schedule_run/1},
      "lead_change" => {%{}, &lead_change/1},
      "life_routine_overdue" => {%{}, &life_routine_overdue/1},
      "landed_workline" => {%{"flag" => "on"}, &landed_workline/1}
    }
  end

  # Staff.assign from one lead to another: the handoff_opened event the office flies across (it shows
  # hand-offs of the last three minutes, so drive soon after seeding)
  defp lead_change(_params) do
    {:ok, %{id: ws}} = Server.Bootstrap.ensure()
    [from, to | _] = for seat <- Server.Workspaces.bench_all(ws), do: Server.Staff.agent_by_name(seat.name)
    {:ok, thread} = Server.Channel.open_thread(%{title: "fixture: a thread changing hands"})
    {:ok, thread} = Server.Staff.assign(thread, from)
    {:ok, _} = Server.Staff.assign(thread, to)
    :ok
  end

  # a life workspace's 'in bed by 23:00' routine: yesterday's due was stamped on time, and today's, a
  # few minutes ago by the server's local clock (a fixed 23:00 would be overdue only after 23:00), has
  # gone unstamped past its window. The routine is backdated so dues have fired.
  defp life_routine_overdue(_params) do
    {:ok, %{id: ws}} = Server.Workspaces.create_from("life", "Life")
    due = DateTime.add(Server.Schedules.local_now(), -5 * 60, :second)

    {:ok, routine} =
      Server.Life.create_routine(ws, %{
        title: "in bed by 23:00",
        every: "#{due.minute} #{due.hour} * * *",
        window_minutes: 0
      })

    born = DateTime.utc_now() |> DateTime.add(-3 * 86_400, :second) |> DateTime.truncate(:second)
    Server.Repo.update_all(from(r in Server.Routine, where: r.id == ^routine.id), set: [created_at: born])
    routine = Server.Repo.reload!(routine)

    now = DateTime.utc_now()
    current = Server.Life.current_due_at(routine, now)
    previous = Server.Life.previous_due_at(routine, current)
    {:ok, _, _} = Server.Life.routine_done(routine.id, previous)
    :ok
  end

  # Workline stage `landed`: open until GitHub merges its PR. flag=on has that PR waiting (the landing
  # label), flag=off a landed workline whose PR was never opened.
  defp landed_workline(%{"flag" => flag}) do
    if flag not in ~w(on off), do: raise(ArgumentError, "landed_workline flag= is on or off, not #{inspect(flag)}")
    {:ok, %{id: ws}} = Server.Bootstrap.ensure()
    slug = "fixture-landed-#{flag}"

    {:ok, thread} =
      Server.Workline.open(%{title: "fixture: a landed workline", slug: slug, stage: "review", workspace_id: ws})

    {:ok, thread} = thread |> Server.Thread.workline_stage_changeset(%{stage: "landed"}) |> Server.Repo.update()

    if flag == "on" do
      url = "https://github.com/fixture/repo/pull/1"

      {:ok, _} =
        Server.Dossier.record_event(%{
          thread_id: thread.id,
          kind: "check_passed",
          correlation: "workline:#{slug}:landing",
          detail: %{"cmd" => "GitHub merge of #{url}", "exit" => 0, "url" => url, "tail" => "published"}
        })
    end

    :ok
  end

  # Needs.failed_jobs: a background job discarded just now (a retry or dismiss from tlon-cli job)
  defp failed_job(_params) do
    discard_job()
    :ok
  end

  defp discard_job do
    {:ok, job} = %{} |> Oban.Job.new(worker: "Server.Jobs.KeepUp", queue: "default") |> Server.Repo.insert()

    job
    |> Ecto.Changeset.change(
      state: "discarded",
      # a verdict is stamped to the second and counts only if it is not older than its item
      attempted_at: DateTime.add(DateTime.utc_now(), -60, :second),
      errors: [%{"error" => "fixture: boom"}]
    )
    |> Server.Repo.update!()
  end

  # Needs.health: the box reading the node is asked for says one vital is over its limit. Held in the
  # node's env, so it lasts until the smoke is torn down.
  defp health_need(%{"what" => what}) do
    reading =
      case what do
        "disk" -> %{tmux: true, disk_pct: 95, mem_pct: 10}
        "mem" -> %{tmux: true, disk_pct: 10, mem_pct: 95}
        "tmux" -> %{tmux: false, disk_pct: 10, mem_pct: 10}
        _ -> raise ArgumentError, "health_need what= is disk, mem or tmux, not #{inspect(what)}"
      end

    Application.put_env(:server, :health_reading, fn -> reading end)
    :ok
  end

  defp settled_need(_params), do: verdict(&Server.Office.Needs.settle(&1, "fixture: a retry fixes it", "uqbar"))

  defp passed_up_need(_params),
    do: verdict(&Server.Office.Needs.pass_up(&1, "fixture: needs a human", "retry it", "uqbar"))

  # Uqbar's verdicts route only with `uqbar_routing` on: turn it on in a config file of this node's own,
  # never the operator's (Settings edits in the smoke land there too)
  defp verdict(record) do
    path = Path.join(System.tmp_dir!(), "smoke-config-#{System.unique_integer([:positive])}.json")
    :ok = Server.OperatorConfig.put("uqbar_routing", true, path)
    Application.put_env(:server, :operator_config_path, path)
    :ok = record.("job:#{discard_job().id}")
  end

  # RUNS ⊘ / 'last ⊘': a script schedule whose one run was cut off by SIGTERM (exit 143)
  defp interrupted_schedule_run(_params) do
    {:ok, %{id: ws}} = Server.Bootstrap.ensure()

    {:ok, s} =
      Server.Schedules.create(%{
        workspace_id: ws,
        kind: "script",
        title: "fixture: a script cut off",
        body: "exit 143",
        cron: "0 3 * * *",
        enabled: false
      })

    run =
      Server.Repo.insert!(%Server.ScheduleRun{
        schedule_id: s.id,
        status: "running",
        started_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    %{status: "interrupted"} = Server.Schedules.perform(run.id)
    :ok
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
          detail: %{
            "agent" => "fixture",
            "tool" => "Bash",
            "summary" => "Bash · echo hi",
            "command" => "echo hi",
            "reason" => "fixture"
          }
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
