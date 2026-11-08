defmodule Server.MCP.ToolTest do
  use ExUnit.Case, async: false

  alias Server.MCP.Tool
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "a seat's cut list is read once per TTL: a re-seat inside it reads the cached list, after it the new one" do
    {:ok, ws} = Workspaces.register(%{name: "Fence cache"})
    {:ok, seat} = Workspaces.seat(ws.id, %{name: "hladik", archetype: "builder"})
    t0 = System.monotonic_time(:millisecond)

    builder_cut = Tool.cut_tools(ws.id, "hladik", t0)
    assert "submit_qa" in builder_cut

    {:ok, _} = Workspaces.unseat(seat.id)
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hladik", archetype: "qa"})

    assert Tool.cut_tools(ws.id, "hladik", t0 + 1) == builder_cut
    refute "submit_qa" in Tool.cut_tools(ws.id, "hladik", t0 + 60_000)
  end

  describe "explain/1" do
    test "every mapped reason is a sentence with a next action, never an inspected term" do
      reasons = [
        :awaiting_operator,
        :terminal,
        :not_a_workline,
        :root_machine_thread,
        :closed,
        :limit_hit,
        :nothing_awaiting,
        :approving,
        :not_landing,
        :epic,
        :initiative,
        :no_repo,
        :unknown_peer,
        :no_threads,
        {:no_thread, 7},
        {:no_agent, "ghost"},
        {:model_cli_timeout, 120, ""},
        {:model_cli_missing, "claude"},
        {:model_cli_exit, 1, "boom"}
      ]

      for reason <- reasons do
        text = Tool.explain(reason)
        assert is_binary(text)
        refute text == inspect(reason), "#{inspect(reason)} was only inspected"
      end

      assert Tool.explain(:awaiting_operator) =~ "operator"
      assert Tool.explain({:no_thread, 7}) =~ "7"
      assert Tool.explain({:no_agent, "ghost"}) =~ "ghost"
      assert Tool.explain({:model_cli_timeout, 120, ""}) =~ "120"
    end

    test "a hand-off refusal reads as Staffing's sentence, one source for both doors" do
      for r <- [:lead_mid_turn, :clocked_out, :off_shift] do
        assert Tool.explain(r) == Server.Staffing.explain(r)
        refute Tool.explain(r) == inspect(r)
      end
    end

    test "an unmapped reason falls back to inspect; a string is verbatim" do
      assert Tool.explain({:something, :odd}) == "{:something, :odd}"
      assert Tool.explain("already a sentence") == "already a sentence"
    end
  end

  describe "DecideProposal.result/1" do
    alias Server.MCP.Tool.DecideProposal

    test "each shape the judge returns says what happened" do
      assert DecideProposal.result({:ok, %Server.Fact{}}) =~ "now supersedes"

      asked = DecideProposal.result({:ok, %Server.Message{id: 9}})
      assert asked =~ "asked the operator"
      assert asked =~ "nothing was superseded"

      assert DecideProposal.result({:ok, %Server.Event{}}) =~ "rejected"
      assert DecideProposal.result({:ok, :odd}) == "{:ok, :odd}"
    end
  end

  test "a name with no seat on the workspace has no cut list" do
    {:ok, ws} = Workspaces.register(%{name: "Fence none"})
    assert Tool.cut_tools(ws.id, "nobody") == []
  end
end
