defmodule Server.Web.HomeLive do
  @moduledoc """
  The one page (one-brain piece D, slice 1): the sidebar (workspaces › threads › crew) on the
  left, a thread on the right — its brief, its conversation, a composer that posts as the
  operator — over exactly the reads and writes asterion and the TUI use (`Board.sidebar/0`,
  `Board.brief/1`, `Channel.recent_messages/2`, `Channel.post/1`). Live: subscribed to the Bus's
  threads, messages and presence topics; any event re-reads the affected model (the DB is the bus,
  §10 — the event is the nudge, the row is the truth).
  """
  use Phoenix.LiveView

  alias Server.Board
  alias Server.Bus
  alias Server.Channel
  alias Server.MCP.Brief
  alias Server.Repo
  alias Server.Thread

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Bus.subscribe_threads()
      Bus.subscribe_messages()
      Bus.subscribe_presence()
      Bus.subscribe_workspaces()
    end

    {:ok, assign(socket, groups: Board.sidebar(), thread: nil, brief: nil, messages: [], draft: "")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Integer.parse(id) do
      {n, ""} -> {:noreply, load_thread(socket, n)}
      _ -> {:noreply, push_patch(socket, to: "/")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, thread: nil, brief: nil, messages: [])}

  defp load_thread(socket, id) do
    case Repo.get(Thread, id) do
      nil ->
        assign(socket, thread: nil, brief: nil, messages: [])

      thread ->
        assign(socket,
          thread: thread,
          brief: thread |> Board.brief() |> Brief.scope(),
          messages: Enum.reverse(Channel.recent_messages(thread, 100))
        )
    end
  end

  @impl true
  def handle_event("compose", %{"body" => body}, %{assigns: %{thread: %Thread{} = thread}} = socket) do
    case String.trim(body) do
      "" ->
        {:noreply, socket}

      text ->
        {:ok, _} = Channel.post(%{thread_id: thread.id, author: operator(), body: text})
        {:noreply, socket |> assign(draft: "") |> load_thread(thread.id)}
    end
  end

  def handle_event("compose", _params, socket), do: {:noreply, socket}

  # Any Bus event: the sidebar re-reads; the open thread re-reads when the event names it.
  @impl true
  def handle_info({_tag, row}, socket) do
    socket = assign(socket, groups: Board.sidebar())

    case socket.assigns.thread do
      %Thread{id: id} when is_integer(id) ->
        if touches?(row, id), do: {:noreply, load_thread(socket, id)}, else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}
  # Does a Bus row concern the open thread? A row ON the thread (message, session, todo…) or the
  # thread's own row — never a message whose own id happens to equal the thread's.
  defp touches?(%Thread{id: tid}, id), do: tid == id
  defp touches?(%{thread_id: tid}, id), do: tid == id
  defp touches?(_row, _id), do: false

  defp operator, do: Application.get_env(:server, :operator, "andrew")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="frame">
      <nav class="rail">
        <Server.Web.PanelsLive.nav panel={:threads} />
        <div :for={g <- @groups}>
          <div class="ws">{g.workspace.icon || "▪"} {g.workspace.name}</div>
          <.link
            :for={t <- g.threads}
            patch={"/threads/#{t.id}"}
            class={["thread", t.root && "root", t.working && "working", @thread && @thread.id == t.id && "current"]}
          >
            {if t.working, do: "●", else: "○"} {t.title}
            <span :if={t.stage} class="stage">[{t.stage}]</span>
            <span :if={t.awaiting} class="flag">⚑ {t.awaiting}</span>
            <span :if={t.lead} class="lead">·{t.lead}</span>
          </.link>
          <div :if={g.crew != []} class="crew">
            crew {Enum.map_join(g.crew, " ", fn c -> (if(c.working, do: "●", else: "○")) <> c.name <> if(c.lead, do: "*", else: "") end)}
          </div>
        </div>
        <div :if={@groups == []} class="meta">(no workspaces)</div>
      </nav>
      <main class="main">
        <div :if={@thread == nil} class="meta">pick a thread</div>
        <div :if={@thread}>
          <h1>{@brief["goal"]}</h1>
          <div class="meta">thread #{@thread.id} · lead {@brief["lead"] || "unstaffed"}</div>

          <div :if={@brief["workline"]} class="panel">
            <span class="label">WORKLINE · {@brief["workline"]["stage"]}</span>
            <span class={if @brief["workline"]["artifact_ok"], do: "ok", else: "bad"}>
              {if @brief["workline"]["artifact_ok"], do: "✓", else: "✗"} {@brief["workline"]["why"]}
            </span>
            <span :if={@brief["workline"]["awaiting"]} class="flag">awaiting {@brief["workline"]["awaiting"]}</span>
          </div>

          <div :if={@brief["todos"]["shown"] != []} class="panel">
            <span class="label">TODOS</span>
            <ul class="list"><li :for={t <- @brief["todos"]["shown"]}>{if t["done_at"], do: "☑", else: "☐"} {t["text"]}</li></ul>
          </div>

          <div :if={@brief["checks"]["shown"] != []} class="panel">
            <span class="label">CHECKS</span>
            <ul class="list"><li :for={c <- @brief["checks"]["shown"]} class={if c["passed"], do: "ok", else: "bad"}>{if c["passed"], do: "✓", else: "✗"} {c["cmd"]}</li></ul>
          </div>

          <div :if={@brief["commits"]["shown"] != []} class="panel">
            <span class="label">COMMITS</span>
            <ul class="list"><li :for={c <- @brief["commits"]["shown"]}><code>{c["sha"]}</code> {c["subject"]} <span class="meta">— {c["author"]}</span></li></ul>
          </div>

          <div class="panel">
            <span class="label">CONVERSATION</span>
            <div :for={m <- @messages} class="msg">
              <span class={["who", if(m.author == operator(), do: "operator", else: "agent")]}>{m.author}</span>
              <span class="when">{m.created_at && Calendar.strftime(m.created_at, "%Y-%m-%d %H:%M")}</span>
              <div class="body">{m.body}</div>
            </div>
            <div :if={@messages == []} class="meta">nothing said yet</div>
            <form class="compose" phx-submit="compose">
              <textarea name="body" placeholder={"post to ##{@thread.id} as #{operator()}"}>{@draft}</textarea>
              <button type="submit">post</button>
            </form>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
