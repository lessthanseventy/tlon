defmodule Server.Repo.Migrations.Core do
  use Ecto.Migration

  # 001 core (spec §9.1). The only domain table day one needs is `collection`:
  # without it, "the world is empty" cannot be told from "this collector has
  # failed three times" (§4, §6). Times are ISO-8601 TEXT stamps; age is computed
  # in the query, never stored. Later tables (fact, event, issue, message,
  # thread, agent) arrive in their own migrations as their step lands.
  def change do
    create table(:collection, primary_key: false) do
      add :source, :text, primary_key: true
      add :last_attempt, :text
      add :last_success, :text
      add :last_error, :text
    end
  end
end
