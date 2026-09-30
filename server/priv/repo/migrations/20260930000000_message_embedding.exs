defmodule Server.Repo.Migrations.MessageEmbedding do
  @moduledoc false
  use Ecto.Migration

  # A message's meaning, for semantic history search (Server.Search.history/3): the same JSON-text
  # vector a fact carries, read for cosine in Elixir, so no Postgres extension is required.
  def change do
    alter table(:message) do
      add :embedding, :text
      add :embedding_model, :text
    end
  end
end
