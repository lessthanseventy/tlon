defmodule Server.Workline.RetroTest do
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Workline.Retro

  setup do
    Server.TestDB.clean!()
    {:ok, t} = Channel.open_thread(%{title: "the hall's taken names"})
    %{thread: t}
  end

  defp bounce(t, why) do
    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: t.id,
        kind: "stage_advanced",
        correlation: "workline:x",
        detail: %{"from" => "review", "to" => "build", "bounced" => why}
      })
  end

  test "a workline never sent back to build asks nothing and banks nothing", %{thread: t} do
    assert {:ok, []} = Retro.run(t, ask: fn _ -> flunk("asked") end)
  end

  test "its bounce reasons go to the model, and at most two concrete lessons are banked as learned facts", %{thread: t} do
    bounce(t, "server:check red: credo, function body nested too deep in recurrence.ex")

    {:ok, _} =
      Channel.post(%{
        thread_id: t.id,
        author: "tlon",
        body: "↩ back to build — sent back by nolan: the help line wraps at 80 cols"
      })

    me = self()

    ask = fn prompt ->
      send(me, {:prompt, prompt})

      {:ok,
       "- Run mix credo --strict on the files you touched before verify\n- Check the help line at 80 columns\n- A third one\nNONE"}
    end

    assert {:ok, [a, b]} = Retro.run(t, ask: ask)
    assert_received {:prompt, prompt}
    assert prompt =~ "nested too deep" and prompt =~ "wraps at 80 cols"
    assert a.kind == "learned" and a.provenance == "derived" and a.thread_id == t.id
    assert a.text == "retro of ##{t.id}: Run mix credo --strict on the files you touched before verify"
    assert b.text =~ "80 columns"
  end

  test "an answer of NONE banks nothing", %{thread: t} do
    bounce(t, "a conflict in wide.ts")
    assert {:ok, []} = Retro.run(t, ask: fn _ -> {:ok, "NONE"} end)
  end
end
