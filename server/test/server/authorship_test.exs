defmodule Server.AuthorshipTest do
  # #679: the one place "who wrote it" is rendered. A stamped row names its seat, pane and session
  # (what a denial is checked against); a NULL says "session unknown", never a guess.
  use ExUnit.Case, async: false

  alias Server.Authorship
  alias Server.Channel
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "qa pass"})
    {:ok, agent} = Staff.register_agent(%{name: "nolan", mandate: "m", engine: "e"})
    %{thread: thread, agent: agent}
  end

  test "label/2 names seat, pane and session", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    assert Authorship.label("nolan", s.id) == "nolan · pane t#{thread.id} %9 · session #{s.id}"
  end

  test "an ended session still renders", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    {:ok, _} = Staff.end_session(s)
    assert Authorship.label("nolan", s.id) == "nolan · pane t#{thread.id} %9 · session #{s.id}"
  end

  test "no pane drops the pane segment", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id})
    assert Authorship.label("nolan", s.id) == "nolan · session #{s.id}"
  end

  test "nil and a vanished session are unknown" do
    assert Authorship.label("tlon", nil) == "tlon · session unknown"
    assert Authorship.label("nolan", 999_999) == "nolan · session unknown"
  end

  test "session_label/1 is the same string without the author", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    assert Authorship.session_label(s.id) == "pane t#{thread.id} %9 · session #{s.id}"
    assert Authorship.session_label(nil) == "session unknown"
  end
end
