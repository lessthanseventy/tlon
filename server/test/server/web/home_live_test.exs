defmodule Server.Web.HomeLiveTest do
  # The web UI (one-brain piece D): the same reads the TUI and asterion use, rendered; a post from
  # the composer lands as the operator's message and the page re-reads on the Bus.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Server.Channel
  alias Server.Web.Endpoint

  @endpoint Endpoint

  setup_all do
    start_supervised!(Endpoint)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "webbed", type: "code", scope: "project", repos: [], roster: []})
    {:ok, thread} = Channel.open_thread(%{title: "the web thread", workspace_id: ws.id})
    %{thread: thread}
  end

  test "the sidebar lists the thread; opening it shows the brief and the conversation", %{thread: t} do
    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "webbed"
    assert html =~ "the web thread"
    assert html =~ "pick a thread"

    # a patch link renders in place — the thread's brief and an empty conversation
    html = view |> element("a.thread", "the web thread") |> render_click()
    assert html =~ "thread ##{t.id}"
    assert html =~ "nothing said yet"
    assert has_element?(view, "form.compose")
  end

  test "the composer posts as the operator and the page shows it", %{thread: t} do
    {:ok, view, _html} = live(build_conn(), "/threads/#{t.id}")
    html = view |> form("form.compose", %{"body" => "hello from the browser"}) |> render_submit()
    assert html =~ "hello from the browser"
    assert html =~ Application.get_env(:server, :operator, "andrew")
    assert [%{author: author, body: "hello from the browser"}] = Channel.recent_messages(t, 5)
    assert author == Application.get_env(:server, :operator, "andrew")
  end

  test "a post from elsewhere reaches the open page through the Bus", %{thread: t} do
    {:ok, view, _html} = live(build_conn(), "/threads/#{t.id}")
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "hronir", body: "posted over MCP"})
    # the Bus event is async; the render after it carries the row
    Process.sleep(50)
    assert render(view) =~ "posted over MCP"
  end

  test "the root layout carries the palette variables and LiveView's JS" do
    conn = get(build_conn(), "/")
    body = html_response(conn, 200)
    assert body =~ "--body:"
    assert body =~ "/live-view/phoenix_live_view.min.js"
  end
end
