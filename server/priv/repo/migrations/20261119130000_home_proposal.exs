defmodule Server.Repo.Migrations.HomeProposal do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:home_proposal) do
      add :source, :string, null: false
      add :key, :string, null: false
      add :text, :text, null: false
      add :why, :text
      add :kind, :string, null: false
      add :who, :string
      add :url, :text
      add :state, :string, null: false, default: "open"
      add :jot_id, :integer
      add :done_text, :text
      add :resolved_at, :utc_datetime
      add :resolved_said_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:home_proposal, [:source, :key])
    create index(:home_proposal, [:state])
  end
end
