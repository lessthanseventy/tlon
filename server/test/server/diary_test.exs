defmodule Server.DiaryTest do
  # What a builder seat did, read from real rows: its landed worklines and the send-backs of the
  # threads it worked on. A read only; the diary writer turns it into lines.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.{Channel, Dossier, Diary, Event, Repo}

  @since ~U[2000-01-01 00:00:00Z]

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
    %{ws: ws}
  end

  defp workline(ws, slug, title) do
    {:ok, thread} = Channel.open_thread(%{workspace_id: ws.id, title: title, slug: slug, stage: "build"})
    thread
  end

  test "a builder who posted on a landed workline is credited with shipping it", %{ws: ws} do
    thread = workline(ws, "stanza", "the stanza")
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "daneri", body: "built the stanza"})
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "lonnrot", body: "reviewed"})

    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "work_landed",
        correlation: "workline:stanza:landing",
        detail: %{"summary" => "landed"}
      })

    assert %{"daneri" => [%{kind: :shipped, thread_id: id, title: "the stanza"}]} = Diary.history(ws.id, @since)
    assert id == thread.id
    refute Map.has_key?(Diary.history(ws.id, @since), "lonnrot")
  end

  test "a send-back is credited to the builder of that thread", %{ws: ws} do
    thread = workline(ws, "lamp", "the lamp")
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "daneri", body: "built the lamp"})

    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "stage_advanced",
        correlation: "workline:lamp",
        detail: %{"from" => "review", "to" => "build", "bounced" => "sent back by lonnrot: the wick"}
      })

    assert %{"daneri" => [%{kind: :bounced, thread_id: _, title: "the lamp"}]} = Diary.history(ws.id, @since)
  end

  test "a landing older than since is left out", %{ws: ws} do
    thread = workline(ws, "old", "the old one")
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "daneri", body: "built it"})

    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "work_landed",
        correlation: "workline:old:landing",
        detail: %{"summary" => "landed"}
      })

    Repo.update_all(from(e in Event, where: e.thread_id == ^thread.id), set: [created_at: ~U[1999-12-31 00:00:00Z]])

    assert Diary.history(ws.id, @since) == %{}
  end

  test "a thread with no builder on it credits nobody", %{ws: ws} do
    thread = workline(ws, "ghost", "no one built this")
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "lonnrot", body: "reviewed only"})

    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "work_landed",
        correlation: "workline:ghost:landing",
        detail: %{"summary" => "landed"}
      })

    assert Diary.history(ws.id, @since) == %{}
  end
end
