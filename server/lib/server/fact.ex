defmodule Server.Fact do
  @moduledoc """
  A durable thing learned (spec §4): the judgement a system cannot derive. One row is one claim with one `provenance` — `stated` (the owner
  said it, verbatim) or `derived` (we produced it) — and reproducibility rides a
  separate axis, `check_cmd`, the command that re-runs the claim. `kind` and
  `provenance` are closed sets the DB CHECKs; the schema does not mirror them.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

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
    # When the conversation it came from happened (nil: not from a conversation, or unknown).
    field :observed_at, :utc_datetime
    # Semantic-recall index (written AFTER the fact, off the write path) — the embedding vector and
    # the model that produced it, so a model swap is a detectable re-embed.
    field :embedding, Server.VectorColumn
    field :embedding_model, :string
    # The operator's manual tombstone — set means out of every recall surface, row kept.
    field :forgotten_at, :utc_datetime
    belongs_to :thread, Server.Thread
    belongs_to :source_session, Server.Session
  end

  # A model sometimes answers with a placeholder ("...") in place of a claim.
  @min_alnum 5

  @doc """
  Scope a fact query to a workspace's memory: a fact belongs to it when it is GLOBAL (no thread —
  the seed self-knowledge) or its thread lives in that workspace. `nil` = every workspace.
  """
  def in_workspace(query, nil), do: query

  def in_workspace(query, workspace_id) do
    ids = from(t in Server.Thread, where: t.workspace_id == ^workspace_id, select: t.id)
    from f in query, where: is_nil(f.thread_id) or f.thread_id in subquery(ids)
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
  DB's own guards (§10) — a bad value raises rather than being re-checked here. A placeholder
  (`junk?/1`) is refused here, so every door that banks — the extractor, `bank_fact`, a stated
  fact — is held to it.
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
      :source_session_id,
      :observed_at
    ])
    |> validate_required([:kind, :text, :provenance])
    |> validate_change(:text, fn :text, text -> if junk?(text), do: [text: "is a placeholder, not a fact"], else: [] end)
    |> Server.Secrets.validate_no_secret(:text)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Whether `text` is too thin to be a claim: fewer than #{@min_alnum} letters or digits."
  def junk?(text), do: length(Regex.scan(~r/[\p{L}\p{N}]/u, text)) < @min_alnum
end
