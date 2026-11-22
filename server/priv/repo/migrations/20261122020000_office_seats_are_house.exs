defmodule Server.Repo.Migrations.OfficeSeatsAreHouse do
  @moduledoc false
  use Ecto.Migration

  # `Server.Roster.specialty_of/1` names the area `house`: a seat still tagged `office` matches no
  # work. A data move, once; `house` seats tagged by hand are not told apart, so there is no way back.
  def up do
    execute("UPDATE workspace_agent SET specialty = 'house' WHERE specialty = 'office'")
  end

  def down, do: :ok
end
