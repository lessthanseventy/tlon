defmodule Server.Office.NeedsDirtyTest do
  use ExUnit.Case, async: false

  alias Server.Office.NeedsDirty

  # The running server is marked by every bus write the rest of the app makes, so a false take on it
  # can't be asserted: the once-per-mark and ceiling rules are held on the callbacks with a state of the test's own.
  @t ~U[2100-01-01 00:00:00Z]

  defp take(state, seconds) do
    {:reply, run?, state} = NeedsDirty.handle_call({:take, DateTime.add(@t, seconds)}, self(), state)
    {run?, state}
  end

  test "a take with nothing changed is false" do
    assert {false, _} = take(%{dirty: false, last: @t}, 10)
  end

  test "a bus event marks it dirty once" do
    {:noreply, state} = NeedsDirty.handle_info({:ticket_filed, %Server.Ticket{}}, %{dirty: false, last: @t})
    assert {true, state} = take(state, 10)
    assert {false, _} = take(state, 20)
  end

  test "it is taken again once the ceiling has passed with no event" do
    assert {true, state} = take(%{dirty: false, last: @t}, 301)
    assert {false, _} = take(state, 302)
  end

  test "the running server is marked by a bus event" do
    NeedsDirty.take()
    :ok = Server.Bus.broadcast({:ticket_filed, %Server.Ticket{}})
    assert NeedsDirty.take()
  end
end
