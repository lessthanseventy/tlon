defmodule Server.Office.Random do
  @moduledoc """
  #random: now and then a coworker posts a joke, a pun, an office meme or a small ASCII bit to the
  workspace's `#random` channel — its one thread, opened on first ask (`thread/1`) and led by
  nobody. Written like the corkboard (`Server.Office.Writer`, over `Server.Office.Banter`'s scene of
  the office); the server picks the author, the model only writes it.

  Chatter, never work: a post (`post/3`) is a `notice` stored already delivered, so the switchboard
  wakes nobody — not a coworker it names, not one live on the thread — and the memory pass and
  recall's embedding never read it; its `@`s are stripped, so it is never an operator mention
  (`Server.Office.Needs`). The thread is left off triage's "nobody leads it".

  Lazy like the corkboard: a post is only written while an office asks (the corkboard poll
  `nudge/1`s it), at most one per workspace every `@every_s` at the office's pace
  (`Writer.every/1`), counted from the thread's last post so a restart doesn't post at once.
  Nothing under pencils down or lights out (`Server.Pause`), or with the banter off.
  """
  use GenServer

  import Ecto.Query

  alias Server.ChannelRow
  alias Server.Message
  alias Server.Office.Banter
  alias Server.Repo
  alias Server.Thread

  require Logger

  @name "random"
  @every_s 4 * 3600
  @max 400
  @voice """
  You write ONE post a coworker drops in the #random channel of a pixel-art office of AI coworkers:
  a joke, a pun, an office meme in words, a fake motivational poster, or a tiny ASCII drawing (at
  most 5 lines). Under 300 characters; in character for their role; about programming, office life,
  their work or the office's day; dry, warm, a little absurd; never cruel; no @mentions, no hashtags.
  Respond with ONLY a JSON object: {"post": "<the post; \\n for a line break>"}
  """

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "The workspace's #random thread, its channel and thread opened on first ask."
  @spec thread(integer()) :: Thread.t()
  def thread(workspace_id) do
    channel = channel(workspace_id)

    Repo.one(
      from t in Thread,
        where:
          t.workspace_id == ^workspace_id and t.channel_id == ^channel.id and t.title == @name and t.state == "open",
        order_by: [asc: t.id],
        limit: 1
    ) || open(workspace_id, channel)
  end

  defp channel(workspace_id) do
    with nil <- Repo.get_by(ChannelRow, workspace_id: workspace_id, name: @name) do
      _ = Server.Channels.create(workspace_id, @name)
      Repo.get_by!(ChannelRow, workspace_id: workspace_id, name: @name)
    end
  end

  # led by nobody: a post there is never a lead's to answer
  defp open(workspace_id, channel) do
    {:ok, t} =
      Server.Channel.open_thread(%{title: @name, workspace_id: workspace_id, channel_id: channel.id, agent_id: nil})

    t
  end

  @doc "Post `body` to the workspace's #random as `author`: a delivered notice that wakes nobody."
  @spec post(integer(), String.t(), String.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def post(workspace_id, author, body) do
    %{thread_id: thread(workspace_id).id, author: author, kind: "notice", body: String.replace(body, "@", "")}
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  @doc "The office is watching: post to #random if one is due. Returns at once."
  @spec nudge(integer()) :: :ok
  def nudge(workspace_id) do
    if GenServer.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:nudge, workspace_id})
    :ok
  end

  @doc false
  def parse(out) do
    Server.JsonBlob.first_valid(out, fn
      %{"post" => p} when is_binary(p) -> if String.trim(p) != "", do: String.slice(String.trim(p), 0, @max)
      _ -> nil
    end)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:nudge, ws}, state) do
    now = System.system_time(:second)
    last = Map.get_lazy(state, ws, fn -> last_post(ws) end)

    if now - last >= Server.Office.Writer.every(@every_s) and allowed?() do
      Task.Supervisor.start_child(Server.TaskSupervisor, fn -> write(ws) end)
      {:noreply, Map.put(state, ws, now)}
    else
      {:noreply, Map.put(state, ws, last)}
    end
  end

  defp allowed?, do: Server.OperatorConfig.banter?() and Server.Pause.state() == :working

  defp last_post(ws) do
    tid = thread(ws).id

    case Repo.one(from m in Message, where: m.thread_id == ^tid, select: max(m.created_at)) do
      nil -> 0
      at -> DateTime.to_unix(at)
    end
  end

  defp write(ws) do
    ctx = Banter.context(ws)

    with [_ | _] <- ctx.crew,
         author = Enum.random(ctx.crew),
         ask = "#{author.name} (#{author.archetype}) posts in #random.",
         {:ok, out} <- Server.Office.Writer.write(@voice <> "\n" <> Banter.scene(ctx) <> "\n\nNOW: " <> ask, ws),
         body when is_binary(body) <- parse(out),
         {:ok, _} <- post(ws, author.name, String.replace(body, "\\n", "\n")) do
      :ok
    else
      other -> Logger.debug("random: nothing posted in workspace #{ws}: #{inspect(other)}")
    end
  end
end
