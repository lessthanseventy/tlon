defmodule Server.Web.PanelsLive do
  @moduledoc """
  The console's other panels, on the web (one-brain piece D, slice 2): TRIAGE (what awaits the
  operator, with the approve verb, and the machine's recent activity), ROSTER (each workspace's
  bench, its live sessions and its tmux windows — and the staffing pass on a button, which the
  service runs with no cockpit open since B/3), TICKETS (the board per workspace) and HEALTH (the
  doctor's report, the queue, who is thinking). Same reads as the TUI; live on the Bus.
  """
  use Phoenix.LiveView

  import Ecto.Query

  alias Server.Board
  alias Server.Bus
  alias Server.Doctor
  alias Server.Presence.Thinking
  alias Server.Repo
  alias Server.Staff
  alias Server.Staffing
  alias Server.Thread
  alias Server.Tickets
  alias Server.Tmux
  alias Server.Workline
  alias Server.Workspaces

  @panels ~w(triage roster tickets health)a

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Bus.subscribe_threads()
      Bus.subscribe_messages()
      Bus.subscribe_sessions()
      Bus.subscribe_tickets()
      Bus.subscribe_presence()
      Bus.subscribe_workspaces()
    end

    {:ok, assign(socket, panel: :triage, flash_line: nil)}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: action}} = socket) when action in @panels do
    {:noreply, socket |> assign(panel: action) |> load()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, push_patch(socket, to: "/triage")}

  defp load(%{assigns: %{panel: :triage}} = socket) do
    rows = Enum.flat_map(Board.sidebar(), fn g -> Enum.map(g.threads, &Map.put(&1, :workspace, g.workspace.name)) end)
    assign(socket, awaiting: Enum.filter(rows, & &1.awaiting), activity: Board.recent_activity(30))
  end

  defp load(%{assigns: %{panel: :roster}} = socket) do
    sessions = Staff.roster()

    workspaces =
      for ws <- Workspaces.all() do
        %{workspace: ws, bench: Workspaces.bench(ws.id), windows: Tmux.list_windows(ws.id)}
      end

    assign(socket, sessions: sessions, workspaces: workspaces)
  end

  defp load(%{assigns: %{panel: :tickets}} = socket) do
    boards =
      for ws <- Workspaces.all() do
        %{workspace: ws, columns: ws.id |> Tickets.in_workspace() |> Enum.group_by(& &1.status)}
      end

    assign(socket, boards: boards)
  end

  defp load(%{assigns: %{panel: :health}} = socket) do
    queue =
      Repo.all(from j in "oban_jobs", group_by: [j.state, j.worker], select: {j.state, j.worker, count(j.id)})

    thinking = for {tid, entries} <- Thinking.thinking_all(), e <- entries, do: Map.put(e, :thread_id, tid)
    assign(socket, doctor: Doctor.report(), queue: queue, thinking: thinking)
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    line =
      with {n, ""} <- Integer.parse(id),
           %Thread{} = thread <- Repo.get(Thread, n),
           {:ok, approved} <- Workline.approve(thread) do
        "approved ##{approved.id} → #{approved.stage}"
      else
        {:error, reason} -> "approve refused: #{inspect(reason)}"
        _ -> "no such thread"
      end

    {:noreply, socket |> assign(flash_line: line) |> load()}
  end

  # The pass waits on harness boots; it runs off the page's process and the roster re-reads on
  # the Bus (a spawned session announces itself).
  def handle_event("staff", _params, socket) do
    Task.Supervisor.start_child(Server.TaskSupervisor, fn -> Staffing.pass() end)
    {:noreply, assign(socket, flash_line: "staffing pass started")}
  end

  @impl true
  def handle_info({_tag, _row}, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="frame">
      <nav class="rail">
        <.nav panel={@panel} />
      </nav>
      <main class="main">
        <div :if={@flash_line} class="meta">{@flash_line}</div>
        <.triage :if={@panel == :triage} awaiting={@awaiting} activity={@activity} />
        <.roster :if={@panel == :roster} sessions={@sessions} workspaces={@workspaces} />
        <.tickets :if={@panel == :tickets} boards={@boards} />
        <.health :if={@panel == :health} doctor={@doctor} queue={@queue} thinking={@thinking} />
      </main>
    </div>
    """
  end

  @doc "The panel links — the rail's head on every page."
  def nav(assigns) do
    ~H"""
    <div class="nav">
      <.link navigate="/">threads</.link>
      <.link :for={p <- [:triage, :roster, :tickets, :health]} patch={"/#{p}"} class={@panel == p && "current"}>{p}</.link>
    </div>
    """
  end

  defp triage(assigns) do
    ~H"""
    <div class="panel">
      <span class="label">NEEDS YOU</span>
      <div :for={t <- @awaiting} class="row">
        <span class="flag">⚑ {t.awaiting}</span>
        <.link navigate={"/threads/#{t.id}"}>#{t.id} {t.title}</.link>
        <span :if={t.stage} class="stage">[{t.stage}]</span>
        <span class="meta">· {t.workspace}</span>
        <button phx-click="approve" phx-value-id={t.id}>approve</button>
      </div>
      <div :if={@awaiting == []} class="meta">nothing awaits you</div>
    </div>
    <div class="panel">
      <span class="label">ACTIVITY</span>
      <div :for={{tag, row} <- @activity} class="row">
        <span class="when">{row.created_at && Calendar.strftime(row.created_at, "%m-%d %H:%M")}</span>
        <span class="meta">{tag}</span>
        <span>{activity_text(tag, row)}</span>
      </div>
    </div>
    """
  end

  defp activity_text(:message_posted, m), do: "#{m.author}: #{String.slice(m.body, 0, 120)}"
  defp activity_text(:fact_banked, f), do: "#{f.kind}: #{String.slice(f.text, 0, 120)}"
  defp activity_text(:event_recorded, e), do: "#{e.kind} #{detail_text(e.detail)}"

  defp detail_text(nil), do: ""
  defp detail_text(d) when is_binary(d), do: d
  defp detail_text(d), do: Jason.encode!(d)

  defp roster(assigns) do
    ~H"""
    <div class="panel">
      <span class="label">ON THE CLOCK</span>
      <div :for={s <- @sessions} class="row">
        <span class={if s.warm?, do: "ok", else: "meta"}>{if s.warm?, do: "●", else: "○"}</span>
        <b>{s.agent}</b> on
        <.link navigate={"/threads/#{s.thread_id}"}>#{s.thread_id} {s.thread_title}</.link>
        <span class="meta">{s.pane_ref}</span>
      </div>
      <div :if={@sessions == []} class="meta">nobody is on the clock</div>
    </div>
    <div :for={w <- @workspaces} class="panel">
      <span class="label">{w.workspace.name}</span>
      <div class="row">
        bench:
        <span :for={c <- w.bench} class={c.lead? && "ok"}>{c.name}<span class="meta">/{c.archetype}</span>{if c.lead?, do: "*"} </span>
        <span :if={w.bench == []} class="meta">(empty)</span>
      </div>
      <div class="row">
        windows:
        <span :for={t <- w.windows}><code>{t.name}</code><span :if={t.thread_id} class="meta">→#{t.thread_id}</span> </span>
        <span :if={w.windows == []} class="meta">(no tmux session)</span>
      </div>
    </div>
    <button phx-click="staff">run the staffing pass now</button>
    """
  end

  defp tickets(assigns) do
    ~H"""
    <div :for={b <- @boards} class="panel">
      <span class="label">{b.workspace.name}</span>
      <div class="columns">
        <div :for={status <- ~w(backlog todo doing done)} class="column">
          <div class="ws">{status}</div>
          <div :for={t <- Map.get(b.columns, status, [])} class="row">
            <span class={"prio " <> t.priority}>{t.priority}</span> {t.title}
            <span :if={t.assignee} class="meta">@{t.assignee}</span>
          </div>
        </div>
      </div>
    </div>
    <div :if={@boards == []} class="meta">(no workspaces)</div>
    """
  end

  defp health(assigns) do
    ~H"""
    <div class="panel">
      <span class="label">STORE</span>
      <div class="row">integrity: <span class={if @doctor.integrity == "ok", do: "ok", else: "bad"}>{@doctor.integrity}</span></div>
      <div class="row">tables: {length(@doctor.tables)}</div>
      <div class="row">pending migrations: <span class={if @doctor.pending == 0, do: "ok", else: "bad"}>{@doctor.pending}</span></div>
    </div>
    <div class="panel">
      <span class="label">QUEUE</span>
      <div :for={{state, worker, n} <- @queue} class="row"><code>{worker}</code> {state}: {n}</div>
      <div :if={@queue == []} class="meta">no jobs yet</div>
    </div>
    <div class="panel">
      <span class="label">THINKING</span>
      <div :for={t <- @thinking} class="row"><b>{t.agent}</b> on #{t.thread_id} <span class="meta">since {t.started_at}</span></div>
      <div :if={@thinking == []} class="meta">nobody is mid-turn</div>
    </div>
    """
  end
end
