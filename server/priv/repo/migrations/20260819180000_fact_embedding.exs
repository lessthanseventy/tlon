defmodule Server.Repo.Migrations.FactEmbedding do
  use Ecto.Migration

  # The forgetting engine's semantic relevance (design: docs/plans/2026-08-19-funes-forgetting-design.md):
  # each fact carries an embedding vector (JSON array TEXT) plus the model that produced it, so a
  # model swap is a detectable re-embed. A free nullable column — no CHECK, so a plain ALTER, not
  # the table rebuild event.kind needs. Never SQL-queried; read for cosine at recall.
  def change do
    alter table(:fact) do
      add :embedding, :text
      add :embedding_model, :string
    end
  end
end
