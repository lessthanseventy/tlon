defmodule Server.Message do
  @moduledoc """
  A message on a thread — the channel, and §4's capture path. `delivered_at` is
  written only by the switchboard's atomic delivery claim (`Server.Switchboard`),
  never by a sender — and it can only ever mean delivered, because there is no
  `read` column (day one cannot prove a read, §5b.3). The sender's `post_changeset`
  cannot touch `delivered_at` at all.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "message" do
    field :author, :string
    field :body, :string
    field :created_at, :utc_datetime
    field :delivered_at, :utc_datetime
    # Optional: the message this one replies to (console §2). A reply is addressed to
    # the replied-to message's author — one of the three ways delivery is targeted.
    field :reply_to, :id
    # The agent-to-agent consult correlation (Server.Consult): `consult_id` links the
    # ask/answer pair, `origin_thread_id` is the asker's thread (where the answer is
    # mirrored back), and `mirrored` marks a copy so the mirror never re-fires on
    # itself (the echo guard). NULL/0 on an ordinary message.
    field :consult_id, :integer
    field :origin_thread_id, :integer
    field :mirrored, :boolean, default: false
    # `chat` is a message; `prompt` is a coworker WAITING on the operator (Server.Attention) — the
    # dialog's options ride `payload`, and `resolved_at`/`resolution` say how it ended.
    field :kind, :string, default: "chat"
    field :payload, :map
    field :resolved_at, :utc_datetime
    field :resolution, :string
    belongs_to :thread, Server.Thread
  end

  @doc """
  A message posted by a participant. A thread, an author, and a body are required
  (§5b). `delivered_at` is intentionally not castable here: the sender's own write
  path can never assert delivery — only the switchboard's atomic claim can.
  """
  def post_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :thread_id,
      :author,
      :body,
      :reply_to,
      :consult_id,
      :origin_thread_id,
      :mirrored,
      :kind,
      :payload
    ])
    |> validate_required([:thread_id, :author, :body])
    |> validate_inclusion(:kind, ["chat", "prompt"])
    |> Server.Secrets.validate_no_secret(:body)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Close a `prompt`: how it ended — `answered: y`, `answered in the terminal`, `superseded`, `window closed`."
  def resolve_changeset(%__MODULE__{kind: "prompt"} = prompt, resolution) when is_binary(resolution) do
    change(prompt, resolved_at: DateTime.truncate(DateTime.utc_now(), :second), resolution: resolution)
  end
end
