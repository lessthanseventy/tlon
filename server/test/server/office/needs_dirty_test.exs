defmodule Server.Office.NeedsDirtyTest do
  use ExUnit.Case, async: false

  alias Server.Office.NeedsDirty

  # Each test starts past any real clock and past the last test's (a monotonic integer: a merely
  # unique one can go backwards), so the setup's take always runs and leaves `last` at `now`.
  setup do
    now = DateTime.add(~U[2100-01-01 00:00:00Z], System.unique_integer([:positive, :monotonic]) * 1000)
    NeedsDirty.take(now)
    %{now: now}
  end

  test "a take with nothing changed is false", %{now: now} do
    refute NeedsDirty.take(DateTime.add(now, 10))
  end

  test "a bus event marks it dirty once", %{now: now} do
    :ok = Server.Bus.broadcast({:ticket_filed, %Server.Ticket{}})
    assert NeedsDirty.take(DateTime.add(now, 10))
    refute NeedsDirty.take(DateTime.add(now, 20))
  end

  test "it is taken again once the ceiling has passed with no event", %{now: now} do
    assert NeedsDirty.take(DateTime.add(now, 301))
    refute NeedsDirty.take(DateTime.add(now, 302))
  end
end
