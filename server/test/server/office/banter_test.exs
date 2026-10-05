defmodule Server.Office.BanterTest do
  # The office's small talk: the weighted draw over kinds of remark, and the whole path with a
  # stand-in model CLI (a script printing a fixed reply and counting its calls).
  use ExUnit.Case, async: false

  alias Server.Office.Banter

  @idle %{name: "hronir", archetype: "builder", lead: false, thread: nil}
  @busy %{
    name: "lonnrot",
    archetype: "reviewer",
    lead: false,
    thread: %{id: 1, title: "fix it", stage: "review", awaiting: nil}
  }
  @quiet %{crew: [@idle], operator: "andrew", awaiting: 0, boss: [], finished: [], tickets: []}

  describe "pick/3" do
    test "a kind with nothing to say is never drawn" do
      # hronir is idle, nobody else works, nothing finished, the boss silent: joke or room only
      kinds = for i <- 0..99, do: elem(Banter.pick(@quiet, @idle, i / 100), 0)
      assert kinds |> Enum.uniq() |> Enum.sort() == [:joke, :room]
    end

    test "the roll walks the weights in order" do
      ctx = %{@quiet | crew: [@idle, @busy]}
      # own_work (lonnrot's) 30, colleague 20, joke 25, room 12 → 87
      assert {:own_work, ask} = Banter.pick(ctx, @busy, 0.0)
      assert ask =~ "lonnrot remarks on their OWN work" and ask =~ "fix it"
      assert {:joke, _} = Banter.pick(ctx, @busy, 55 / 87)
      assert {:room, _} = Banter.pick(ctx, @busy, 80 / 87)
    end

    test "the boss is fair game whenever they have spoken, not only when something waits" do
      ctx = %{@quiet | boss: [~s(- "make it look nice")]}
      kinds = for i <- 0..199, do: elem(Banter.pick(ctx, @idle, i / 200), 0)
      assert :boss in kinds
      assert {:boss, ask} = Enum.find(for(i <- 0..199, do: Banter.pick(ctx, @idle, i / 200)), &(elem(&1, 0) == :boss))
      assert ask =~ "make it look nice"
    end
  end

  describe "lines/1" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})

      dir = Path.join(System.tmp_dir!(), "banter-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      cli = Path.join(dir, "model")
      calls = Path.join(dir, "calls")

      File.write!(cli, """
      #!/bin/sh
      echo x >> #{calls}
      echo 'thinking about it'
      echo '{"line": "I have rebased my feelings onto main."}'
      """)

      File.chmod!(cli, 0o755)
      Application.put_env(:server, :banter_cmd, cli)

      on_exit(fn ->
        Application.delete_env(:server, :banter_cmd)
        File.rm_rf!(dir)
      end)

      start_supervised!(Banter)
      %{ws: ws, calls: calls}
    end

    test "a poll asks for a line, a later poll has it, and the cadence holds", %{ws: ws, calls: calls} do
      assert Banter.lines(ws.id) == []

      said =
        Enum.find_value(1..50, fn _ -> Process.sleep(50) && match?([_], Banter.lines(ws.id)) && Banter.lines(ws.id) end)

      assert [%{agent: "hronir", line: "I have rebased my feelings onto main.", kind: kind}] = said
      assert kind in [:joke, :room]
      assert File.read!(calls) == "x\n"
    end

    test "with banter off there is nothing, and nothing is asked", %{ws: ws} do
      stop_supervised!(Banter)
      assert Banter.lines(ws.id) == []
    end
  end

  test "a reply with no line is dropped" do
    assert Banter.parse("no json here") == nil
    assert Banter.parse(~s({"line": "  "})) == nil
    assert Banter.parse(~s(ok {"line": " hi "})) == "hi"
  end
end
