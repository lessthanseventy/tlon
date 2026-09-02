defmodule Server.Fact do
  @moduledoc """
  A durable thing learned (spec §4): the judgement a system cannot derive. One row is one claim with one `provenance` — `stated` (the owner
  said it, verbatim) or `derived` (we produced it) — and reproducibility rides a
  separate axis, `check_cmd`, the command that re-runs the claim. `kind` and
  `provenance` are closed sets the DB CHECKs; the schema does not mirror them.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "fact" do
    field :kind, :string
    field :text, :string
    field :provenance, :string
    field :check_cmd, :string
    field :intent, :string
    field :incident, :string
    field :taught, :string
    field :supersedes, :id
    field :created_at, :utc_datetime
    # Semantic-recall index (written AFTER the fact, off the write path) — the embedding vector and
    # the model that produced it, so a model swap is a detectable re-embed.
    field :embedding, Server.VectorColumn
    field :embedding_model, :string
    # The operator's manual tombstone — set means out of every recall surface, row kept.
    field :forgotten_at, :utc_datetime
    belongs_to :thread, Server.Thread
    belongs_to :source_session, Server.Session
  end

  @doc "Attach an embedding vector + its model to an existing fact (not part of the write path)."
  def embedding_changeset(%__MODULE__{} = fact, vector, model) when is_list(vector) do
    change(fact, embedding: vector, embedding_model: model)
  end

  @doc "Tombstone a fact — stamps `forgotten_at`; the row and its provenance stay."
  def forget_changeset(%__MODULE__{} = fact) do
    change(fact, forgotten_at: DateTime.utc_now(:second))
  end

  @doc """
  Bank a fact. `kind`, `text`, and `provenance` are required; the closed sets on
  `kind`/`provenance` and the FKs on `thread`/`supersedes`/`source_session` are the
  DB's own guards (§10) — a bad value raises rather than being re-checked here.
  """
  def bank_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :thread_id,
      :kind,
      :text,
      :provenance,
      :check_cmd,
      :intent,
      :incident,
      :taught,
      :supersedes,
      :source_session_id
    ])
    |> validate_required([:kind, :text, :provenance])
    |> validate_no_secret(:text)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  # Refuse a fact whose text carries an obvious credential (total-recall slice B): the ledger — and
  # the automated capture that will feed it — must never store a secret. Returned as a changeset
  # error, so it rides the same {:error, changeset} path as any other invalid write.
  defp validate_no_secret(changeset, field) do
    case Server.Secrets.scan(get_field(changeset, field)) do
      :ok ->
        changeset

      {:secret, label} ->
        add_error(changeset, field, "looks like a secret (#{label}); tlon does not store credentials")
    end
  end
end
