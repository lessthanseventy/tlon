defmodule Server.Office.NeedsTest do
  # Everything waiting on the operator, as one list built from the state that already says so —
  # blocking first, then what to decide when convenient.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Office.Needs

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Needy"})
    %{ws: ws}
  end

  defp kinds(ws), do: Needs.list() |> Enum.filter(&(&1.workspace_id in [ws.id, nil])) |> Enum.map(&{&1.kind, &1.level})

  test "a coworker's question is blocking, and answering it takes it off the list", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "q", workspace_id: ws.id})
    {:ok, _} = Server.Attention.ask(t.id, "daneri", "A or B?")
    assert [%{kind: "question", level: "blocking", thread_id: tid, text: "A or B?"}] = Needs.list()
    assert tid == t.id
    {:ok, _} = Server.Attention.respond(t.id, "andrew", "A")
    assert Needs.list() == []
  end

  test "a workline at its gate is a gate; one red at verify is a failed verify", %{ws: ws} do
    # a machine-born intent parks at its gate before any artifact, by design
    {:ok, _} =
      Server.Workline.flag(
        %{title: "g", slug: "gate-#{System.unique_integer([:positive])}", workspace_id: ws.id},
        "a breach"
      )

    {:ok, red} =
      Server.Workline.open(%{
        title: "r",
        slug: "red-#{System.unique_integer([:positive])}",
        stage: "verify",
        workspace_id: ws.id
      })

    {:ok, _} =
      Server.Dossier.record_check(%{
        thread_id: red.id,
        cmd: "mise run check",
        exit: 1,
        tail: "boom",
        correlation: "workline:#{red.slug}:verify"
      })

    assert Enum.sort(kinds(ws)) == Enum.sort([{"gate", "blocking"}, {"verify_failed", "blocking"}])
  end

  test "an @mention of the operator nobody has answered is to decide; a reply after it settles it", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "m", workspace_id: ws.id})

    {:ok, _} =
      Channel.post(%{thread_id: t.id, author: "tertius", body: "@andrew I'll raise the EPIPE as its own ticket?"})

    assert [{"mention", "decide"}] = kinds(ws)
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "andrew", body: "yes please"})
    assert kinds(ws) == []
  end

  test "blocking comes before deciding, oldest first within each", %{ws: ws} do
    {:ok, a} = Channel.open_thread(%{title: "a", workspace_id: ws.id})
    {:ok, b} = Channel.open_thread(%{title: "b", workspace_id: ws.id})
    {:ok, _} = Channel.post(%{thread_id: a.id, author: "yu", body: "@andrew fyi"})
    {:ok, _} = Server.Attention.ask(b.id, "yu", "blocked on you")
    assert [%{level: "blocking"}, %{level: "decide"}] = Needs.list()
  end
end
