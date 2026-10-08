defmodule Server.Repo.Migrations.UqbarIsACitizen do
  @moduledoc false
  use Ecto.Migration

  # Uqbar design §6: the operator's Claude Code session is a citizen named uqbar, seated on no bench
  # (`Server.Outside`), so its posts stop being signed as the operator.
  def up do
    execute("""
    INSERT INTO agent (name, mandate, engine, created_at)
    SELECT 'uqbar', 'outside', 'claude-code', now()
    WHERE NOT EXISTS (SELECT 1 FROM agent WHERE name = 'uqbar')
    """)
  end

  def down do
    execute("DELETE FROM agent WHERE name = 'uqbar' AND NOT EXISTS (SELECT 1 FROM workspace_agent wa WHERE wa.agent_id = agent.id)")
  end
end
