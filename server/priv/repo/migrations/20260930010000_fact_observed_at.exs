defmodule Server.Repo.Migrations.FactObservedAt do
  @moduledoc false
  use Ecto.Migration

  # When the conversation a fact came from happened. `created_at` stays when it was banked, which the
  # forgetting curve decays from; an import or a late pass can put the conversation long before it.
  def change do
    alter table(:fact) do
      add :observed_at, :utc_datetime
    end
  end
end
