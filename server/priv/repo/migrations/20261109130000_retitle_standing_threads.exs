defmodule Server.Repo.Migrations.RetitleStandingThreads do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("UPDATE thread SET title = 'the front desk' WHERE scope = 'machine' AND stage IS NULL AND title = 'lobby'")
  end

  def down do
    execute("UPDATE thread SET title = 'lobby' WHERE scope = 'machine' AND stage IS NULL AND title = 'the front desk'")
  end
end
