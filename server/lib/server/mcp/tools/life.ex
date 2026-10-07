defmodule Server.MCP.Tool.LifeStatus do
  @moduledoc "The LIFE status for a workspace: xp, level, next_level_at, streaks, due, quests, today."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
  end

  @impl true
  def execute(params, frame), do: ok(frame, Server.Life.status(params.workspace_id))
end

defmodule Server.MCP.Tool.RoutineCreate do
  @moduledoc "A new ROUTINE: recurring, yours. `every` is a cron expression or @daily/@weekly."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
    field :title, :string, required: true
    field :every, :string, required: true
    field :window_minutes, :integer, default: 60
    field :xp, :integer, default: 10
    field :tile, :string
  end

  @impl true
  def execute(params, frame) do
    {workspace_id, attrs} = Map.pop!(params, :workspace_id)
    reply(frame, Server.Life.create_routine(workspace_id, attrs), fn r -> %{"routine_id" => r.id} end)
  end
end

defmodule Server.MCP.Tool.RoutineUpdate do
  @moduledoc "Edit a ROUTINE's mutable fields, by id."
  use Server.MCP.Tool

  alias Server.Repo
  alias Server.Routine

  schema do
    field :routine_id, :integer, required: true
    field :title, :string
    field :every, :string
    field :window_minutes, :integer
    field :xp, :integer
    field :tile, :string
    field :enabled, :boolean
  end

  @impl true
  def execute(params, frame) do
    {routine_id, attrs} = Map.pop!(params, :routine_id)

    case Repo.get(Routine, routine_id) do
      nil -> fail(frame, "no such routine #{routine_id}")
      routine -> reply(frame, Server.Life.update_routine(routine, attrs), fn r -> %{"routine_id" => r.id} end)
    end
  end
end

defmodule Server.MCP.Tool.RoutineDone do
  @moduledoc "Stamp a ROUTINE done now — \"I brushed my teeth\". Returns level_up if it crossed a level."
  use Server.MCP.Tool

  schema do
    field :routine_id, :integer, required: true
  end

  @impl true
  def execute(params, frame) do
    case Server.Life.routine_done(params.routine_id) do
      {:ok, run, level_up} -> ok(frame, %{"run_id" => run.id, "level_up" => level_up})
      {:error, reason} -> fail(frame, to_string(reason))
    end
  end
end

defmodule Server.MCP.Tool.QuestCreate do
  @moduledoc "A new QUEST: one-off, due optional — \"book the dentist\"."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
    field :title, :string, required: true
    field :due_at, :string
    field :xp, :integer, default: 10
  end

  @impl true
  def execute(params, frame) do
    {workspace_id, attrs} = Map.pop!(params, :workspace_id)
    reply(frame, Server.Life.create_quest(workspace_id, attrs), fn q -> %{"quest_id" => q.id} end)
  end
end

defmodule Server.MCP.Tool.QuestDone do
  @moduledoc "Stamp a QUEST done now. Returns level_up if it crossed a level."
  use Server.MCP.Tool

  schema do
    field :quest_id, :integer, required: true
  end

  @impl true
  def execute(params, frame) do
    case Server.Life.quest_done(params.quest_id) do
      {:ok, quest, level_up} -> ok(frame, %{"quest_id" => quest.id, "level_up" => level_up})
      {:error, reason} -> fail(frame, to_string(reason))
    end
  end
end
