defmodule Server.Repo.Migrations.DropHomeTables do
  @moduledoc false
  use Ecto.Migration

  @tables ~w(jot home_keep home_slot home_proposal home_agenda home_bank_transactions)a

  def up do
    for table <- @tables, do: drop_if_exists(table(table))
  end

  def down do
    raise Ecto.MigrationError, message: "the home's tables are not restored by a rollback; pg_restore the backup"
  end
end
