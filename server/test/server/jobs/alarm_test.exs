defmodule Server.Jobs.AlarmTest do
  # A discarded job is one line to the operator on the standing thread — delivered, never a wake,
  # never a flood (piece A).
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Jobs.Alarm
  alias Server.Message
  alias Server.Repo
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, general} = Channel.open_thread(%{title: "general", scope: "machine", workspace_id: ws.id})
    %{general: general}
  end

  defp discarded(worker, error), do: %{state: :discarded, worker: worker, error: error, kind: :error}

  test "a discard posts once, delivered; the same discard again is skipped; a retry posts nothing", %{general: g} do
    meta = discarded("Server.Jobs.Staff", %RuntimeError{message: "tmux: enoent\n    (elixir) lib/system.ex"})
    :ok = Alarm.handle([:oban, :job, :exception], %{}, meta, nil)
    :ok = Alarm.handle([:oban, :job, :exception], %{}, meta, nil)
    :ok = Alarm.handle([:oban, :job, :exception], %{}, %{meta | state: :failure}, nil)

    assert [%Message{author: "tlon", body: body, delivered_at: %DateTime{}}] =
             Repo.all(from m in Message, where: m.thread_id == ^g.id)

    assert body == "⚠ job Server.Jobs.Staff discarded: tmux: enoent"
  end
end
