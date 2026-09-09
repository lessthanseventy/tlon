defmodule Server.Channels do
  @moduledoc """
  Channels (UX slice 1b, 2026-09-08): workspace → channels → threads, Slack's exactly. Every
  workspace has `#general` (`ensure_general/1`, run at workspace registration and lazily by
  `general/1`); topic channels come and go by name; a thread lives in one channel and `move/2`
  puts it in another of the SAME workspace. Deleting a topic channel rehomes its threads in
  #general; #general cannot be deleted. Announces on the Bus like every context.
  """

  import Ecto.Query

  alias Server.Bus
  alias Server.ChannelRow
  alias Server.Repo
  alias Server.Thread

  @doc "The workspace's #general, created on first ask."
  @spec general(integer()) :: ChannelRow.t()
  # a thread with no workspace (a test fixture, a pre-bootstrap open) has no channel either
  def general(nil), do: nil

  def general(workspace_id) do
    case Repo.get_by(ChannelRow, workspace_id: workspace_id, kind: "general") do
      nil -> ensure_general!(workspace_id)
      channel -> channel
    end
  end

  defp ensure_general!(workspace_id) do
    %{workspace_id: workspace_id, name: "general", kind: "general"}
    |> ChannelRow.create_changeset()
    |> Repo.insert!(on_conflict: :nothing)

    Repo.get_by!(ChannelRow, workspace_id: workspace_id, kind: "general")
  end

  @doc "A workspace's channels: #general first, then topics by name."
  @spec in_workspace(integer()) :: [ChannelRow.t()]
  def in_workspace(workspace_id) do
    _ = general(workspace_id)

    Repo.all(
      from(c in ChannelRow,
        where: c.workspace_id == ^workspace_id,
        order_by: [
          asc: fragment("CASE WHEN ? = 'general' THEN 0 ELSE 1 END", c.kind),
          asc: c.name
        ]
      )
    )
  end

  @doc "A channel by id, or nil."
  def get(id), do: Repo.get(ChannelRow, id)

  @doc "Create a topic channel. `{:ok, channel}` | `{:error, changeset}` (a taken name is a changeset error)."
  @spec create(integer(), String.t()) :: {:ok, ChannelRow.t()} | {:error, Ecto.Changeset.t()}
  def create(workspace_id, name) do
    %{workspace_id: workspace_id, name: name, kind: "topic"}
    |> ChannelRow.create_changeset()
    |> Repo.insert()
    |> Bus.announce(:channel_created)
  end

  @doc "Move a thread into another channel of its own workspace."
  @spec move(Thread.t(), integer()) ::
          {:ok, Thread.t()} | {:error, :no_channel | :other_workspace | Ecto.Changeset.t()}
  def move(%Thread{} = thread, channel_id) do
    case get(channel_id) do
      nil ->
        {:error, :no_channel}

      %ChannelRow{workspace_id: wid} when wid != thread.workspace_id ->
        {:error, :other_workspace}

      _channel ->
        thread
        |> Ecto.Changeset.change(channel_id: channel_id)
        |> Repo.update()
        |> Bus.announce(:thread_moved)
    end
  end

  @doc "Delete a topic channel (a row, or its id); its threads go home to #general. #general is refused."
  @spec delete(ChannelRow.t() | integer()) :: {:ok, ChannelRow.t()} | {:error, :general | :no_channel}
  # by id — the console holds sidebar maps, not rows
  def delete(id) when is_integer(id) do
    case get(id) do
      %ChannelRow{} = channel -> delete(channel)
      nil -> {:error, :no_channel}
    end
  end

  def delete(%ChannelRow{kind: "general"}), do: {:error, :general}

  def delete(%ChannelRow{} = channel) do
    home = general(channel.workspace_id)

    Repo.update_all(from(t in Thread, where: t.channel_id == ^channel.id),
      set: [channel_id: home.id]
    )

    channel |> Repo.delete() |> Bus.announce(:channel_deleted)
  end
end
