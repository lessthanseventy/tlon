defmodule Server.DiaryTest do
  # What a builder seat did, read from real rows: its landed worklines and the send-backs of the
  # threads it worked on. A read only; the diary writer turns it into lines.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.{Channel, Diary, Dossier, Event, Repo, Soul}

  @since ~U[2000-01-01 00:00:00Z]

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
    dir = Path.join(System.tmp_dir!(), "diary-#{System.pid()}-#{System.unique_integer([:positive])}")
    Application.put_env(:server, :souls_dir, dir)

    on_exit(fn ->
      Application.put_env(:server, :souls_dir, Path.join(System.tmp_dir!(), "tlon-test-souls-unset"))
      File.rm_rf!(dir)
    end)

    %{ws: ws, dir: dir}
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

  describe "write/3" do
    @soul "## Wants\nA quiet desk.\n\n## Diary\n"
    @today ~D[2026-10-14]

    setup %{dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "daneri.md"), @soul)
      on_exit(fn -> Application.put_env(:server, :generator_cmd, "/nonexistent/tlon-test-generator") end)
      :ok
    end

    defp entry(kind, title), do: %{kind: kind, thread_id: 1, title: title, at: ~U[2026-10-10 00:00:00Z]}

    # a stand-in model CLI that prints `reply`
    defp stub_model(%{dir: dir}, reply) do
      File.mkdir_p!(dir)
      cli = Path.join(dir, "model")
      File.write!(cli, "#!/bin/sh\ncat <<'EOF'\n#{reply}\nEOF\n")
      File.chmod!(cli, 0o755)
      Application.put_env(:server, :generator_cmd, cli)
    end

    test "with the model unavailable, one dated fallback line per item", %{dir: dir} do
      assert :ok = Diary.write("daneri", [entry(:shipped, "the stanza"), entry(:bounced, "the lamp")], @today)

      assert File.read!(Path.join(dir, "daneri.md")) ==
               @soul <> "- 2026-10-14: shipped \"the stanza\".\n- 2026-10-14: sent back on \"the lamp\".\n"
    end

    test "the model's lines are used, dated, at most three, each capped", ctx do
      stub_model(ctx, "here they are:\n- the stanza sang at last.\n- a second line.\n- third.\n- fourth, dropped.")

      assert :ok = Diary.write("daneri", [entry(:shipped, "the stanza")], @today)
      assert Soul.diary("daneri") == ["- 2026-10-14: the stanza sang at last.", "- 2026-10-14: a second line.", "- 2026-10-14: third."]
    end

    test "a model reply with no diary lines falls back to the history", ctx do
      stub_model(ctx, "I cannot do that.")
      assert :ok = Diary.write("daneri", [entry(:shipped, "the stanza")], @today)
      assert Soul.diary("daneri") == ["- 2026-10-14: shipped \"the stanza\"."]
    end

    test "no items writes nothing" do
      assert :ok = Diary.write("daneri", [], @today)
      assert Soul.diary("daneri") == []
    end

    test "a seat with no soul file is an error and no file is made", %{dir: dir} do
      assert {:error, :no_soul} = Diary.write("nobody", [entry(:shipped, "x")], @today)
      refute File.exists?(Path.join(dir, "nobody.md"))
    end
  end
end
