defmodule Server.Jobs.DiaryTest do
  # The weekly diary: each builder seat with a soul file gets its week's lines once, and a re-run
  # within the week writes nothing more.
  use ExUnit.Case, async: false

  alias Server.{Channel, Dossier, Jobs.Diary, Soul}

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})

    dir = Path.join(System.tmp_dir!(), "diary-job-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "daneri.md"), "## Wants\nA quiet desk.\n\n## Diary\n")
    File.write!(Path.join(dir, "lonnrot.md"), "## Wants\nA quiet desk.\n\n## Diary\n")
    Application.put_env(:server, :souls_dir, dir)
    Application.put_env(:server, :generator_cmd, "/nonexistent/tlon-test-generator")

    on_exit(fn ->
      Application.put_env(:server, :souls_dir, Path.join(System.tmp_dir!(), "tlon-test-souls-unset"))
      File.rm_rf!(dir)
    end)

    %{ws: ws}
  end

  defp land(ws, slug, title, builder) do
    {:ok, thread} = Channel.open_thread(%{workspace_id: ws.id, title: title, slug: slug, stage: "build"})
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: builder, body: "built #{slug}"})

    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "work_landed",
        correlation: "workline:#{slug}:landing",
        detail: %{"summary" => "landed"}
      })

    thread
  end

  test "a builder's landed workline shows in its diary, once across re-runs", %{ws: ws} do
    land(ws, "stanza", "the stanza", "daneri")

    assert :ok = Diary.perform(%Oban.Job{})
    assert [line] = Soul.diary("daneri")
    assert line =~ ~s(shipped "the stanza")

    assert :ok = Diary.perform(%Oban.Job{})
    assert Soul.diary("daneri") == [line]
  end

  test "a landing written in last week's run is not written again the next Monday", %{ws: ws} do
    import Ecto.Query

    thread = land(ws, "stanza", "the stanza", "daneri")
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)
    Server.Repo.update_all(from(e in Server.Event, where: e.thread_id == ^thread.id), set: [created_at: seven_days_ago])

    written = Date.to_iso8601(Date.add(Date.utc_today(), -7))

    File.write!(
      Path.join(Application.get_env(:server, :souls_dir), "daneri.md"),
      "## Wants\nA quiet desk.\n\n## Diary\n- #{written}: shipped \"the stanza\".\n"
    )

    assert :ok = Diary.perform(%Oban.Job{})
    assert [_only] = Soul.diary("daneri")
  end

  test "a seat with no history gets no line", %{ws: ws} do
    land(ws, "stanza", "the stanza", "daneri")

    assert :ok = Diary.perform(%Oban.Job{})
    assert Soul.diary("lonnrot") == []
  end

  test "a builder with no soul file is skipped and no file is made", %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "atlas", archetype: "builder"})
    land(ws, "map", "the map", "atlas")

    assert :ok = Diary.perform(%Oban.Job{})
    refute File.exists?(Path.join(Application.get_env(:server, :souls_dir), "atlas.md"))
  end
end
