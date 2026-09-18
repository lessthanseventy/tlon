defmodule Server.Web.PanelsLiveTest do
  # The other panels on the web (one-brain D/2): the same reads the TUI renders, and the approve
  # verb from the browser.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Server.Channel
  alias Server.Tickets
  alias Server.Web.Endpoint
  alias Server.Workline

  @endpoint Endpoint

  setup_all do
    start_supervised!(Endpoint)
    :ok
  end

  setup do
    Server.TestDB.clean!()

    {:ok, ws} =
      Server.Workspaces.register(%{
        name: "webbed",
        type: "code",
        scope: "project",
        repos: [],
        roster: [%{archetype: "builder", name: "hronir"}]
      })

    # approve materialises + commits intent.md under the workline root: a throwaway git repo, never
    # the checkout this suite runs in
    tmp = Path.join(System.tmp_dir!(), "tlon-panels-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["-C", tmp, "init", "-q"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.email", "t@t"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.name", "t"], stderr_to_stdout: true)
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    %{ws: ws}
  end

  test "triage lists what awaits the operator and the recent activity; approve moves the gate", %{ws: ws} do
    {:ok, parked} =
      Workline.flag(%{title: "maintain: x stalled", slug: "maint-x", workspace_id: ws.id}, "breach: evidence")

    {:ok, thread} = Channel.open_thread(%{title: "chatter", workspace_id: ws.id})
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "hronir", body: "hello triage"})

    {:ok, view, html} = live(build_conn(), "/triage")
    assert html =~ "NEEDS YOU"
    assert html =~ "maintain: x stalled"
    assert html =~ "hello triage"

    html = view |> element("button", "approve") |> render_click()
    assert html =~ "approved ##{parked.id}"
    assert Server.Repo.get!(Server.Thread, parked.id).awaiting == nil
  end

  test "roster shows the bench, the live sessions and the windows", %{ws: ws} do
    {:ok, thread} = Channel.open_thread(%{title: "staffed", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(thread.id, "hronir")
    {:ok, agent} = {:ok, Server.Staff.agent_by_name("hronir")}
    {:ok, _} = Server.Staff.start_session(%{thread_id: thread.id, agent_id: agent.id, pane_ref: "w1:1"})

    {:ok, _view, html} = live(build_conn(), "/roster")
    assert html =~ "ON THE CLOCK"
    assert html =~ "hronir"
    assert html =~ "staffed"
    assert html =~ "webbed"
    assert html =~ "run the staffing pass"
  end

  test "tickets renders the board by status", %{ws: ws} do
    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "fix the rail", status: "todo", priority: "high"})

    {:ok, _view, html} = live(build_conn(), "/tickets")
    assert html =~ "fix the rail"
    assert html =~ "todo"
  end

  test "health renders the doctor's report and the queue" do
    {:ok, _view, html} = live(build_conn(), "/health")
    assert html =~ "integrity"
    assert html =~ "QUEUE"
  end
end
