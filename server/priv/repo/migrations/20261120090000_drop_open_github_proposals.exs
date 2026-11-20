defmodule Server.Repo.Migrations.DropOpenGithubProposals do
  @moduledoc false
  use Ecto.Migration

  def up, do: execute("DELETE FROM home_proposal WHERE source = 'github' AND state = 'open'")

  def down, do: :ok
end
