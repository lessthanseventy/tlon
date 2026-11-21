defmodule Server.Repo.Migrations.QaSeatsAreBuilders do
  @moduledoc false
  use Ecto.Migration

  # The qa archetype is gone from `Server.Profiles`: a seat still cast as one would resolve to no
  # role. A data move, once; which seats were qa is not kept, so there is no way back.
  def up do
    execute("UPDATE workspace_agent SET archetype = 'builder' WHERE archetype = 'qa'")
  end

  def down, do: :ok
end
