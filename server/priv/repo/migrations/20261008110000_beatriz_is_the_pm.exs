defmodule Server.Repo.Migrations.BeatrizIsThePm do
  @moduledoc false
  use Ecto.Migration

  # Roster design §5: beatriz leaves the planners to be the Machine workspace's PM. A data move,
  # once; a bench without her is left as it is, and her seat elsewhere is that workspace's.
  def up do
    execute(recast("planner", "pm"))
  end

  def down do
    execute(recast("pm", "planner"))
  end

  defp recast(from, to) do
    """
    UPDATE workspace_agent wa SET archetype = '#{to}'
    FROM agent a, workspace w
    WHERE wa.agent_id = a.id AND wa.workspace_id = w.id
      AND a.name = 'beatriz' AND w.name = 'Machine' AND wa.archetype = '#{from}'
    """
  end
end
