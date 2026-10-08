defmodule Server.Repo.Migrations.NolanIsQa do
  @moduledoc false
  use Ecto.Migration

  # Roster design §5: nolan leaves the builders to be the Machine workspace's QA. A data move,
  # once; a bench without him is left as it is, and his seat elsewhere is that workspace's.
  def up do
    execute(recast("builder", "qa"))
  end

  def down do
    execute(recast("qa", "builder"))
  end

  defp recast(from, to) do
    """
    UPDATE workspace_agent wa SET archetype = '#{to}'
    FROM agent a, workspace w
    WHERE wa.agent_id = a.id AND wa.workspace_id = w.id
      AND a.name = 'nolan' AND w.name = 'Machine' AND wa.archetype = '#{from}'
    """
  end
end
