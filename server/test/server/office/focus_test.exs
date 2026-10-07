defmodule Server.Office.FocusTest do
  # "Show me thread N" from one operator surface to another (the desktop's alert → the office TUI):
  # the newest request, with when, so a surface acts on each one once.
  use ExUnit.Case, async: false

  alias Server.Office.Focus

  test "the newest request is what a surface reads, stamped so it acts once" do
    Focus.request(7)
    assert %{thread_id: 7, at: at7} = Focus.latest()
    Focus.request(9)
    assert %{thread_id: 9, at: at9} = Focus.latest()
    assert at9 >= at7
  end
end
