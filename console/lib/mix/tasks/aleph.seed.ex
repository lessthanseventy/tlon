defmodule Mix.Tasks.Console.Seed do
  @shortdoc "Seed the funes DB with sample threads/agents/sessions/messages for the cockpit"
  @moduledoc """
  Populate `TLON_DB` with a small, believable workspace so the cockpit has something to render and
  react to. Idempotent: re-running won't duplicate agents, threads, or a thread's opening messages.
  Writes only through funes' public API (never raw rows) — the same path agents and the human use.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  alias Server.Channel
  alias Server.Dossier
  alias Server.Staff

  @requirements ["app.config"]

  @agents [
    %{name: "Sandra", mandate: "review & merge PRs", engine: "claude-opus-4-8"},
    %{name: "Robert", mandate: "triage the inbox", engine: "claude-sonnet-5"},
    %{name: "Carl", mandate: "hunt flaky tests", engine: "claude-haiku-4-5"}
  ]

  @threads [
    %{title: "review PR 329", lead: "Sandra"},
    %{title: "triage inbox", lead: "Robert"},
    %{title: "flaky test hunt", lead: "Carl"}
  ]

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:console)

    agents = Map.new(@agents, &{&1.name, ensure_agent(&1)})

    Enum.each(@threads, fn %{title: title, lead: lead} ->
      thread = ensure_thread(title)
      Staff.assign(thread, agents[lead])
      ensure_session(thread, agents[lead])
      seed_chatter(thread, lead)
      seed_brief(thread, lead)
    end)

    Mix.shell().info("aleph: seeded #{length(@agents)} agents and #{length(@threads)} threads.")
  end

  defp ensure_agent(%{name: name} = attrs) do
    case Staff.agent_by_name(name) do
      nil ->
        {:ok, agent} = Staff.register_agent(attrs)
        agent

      agent ->
        agent
    end
  end

  defp ensure_thread(title) do
    case Enum.find(Channel.open_threads(), &(&1.title == title)) do
      nil ->
        {:ok, thread} = Channel.open_thread(%{title: title})
        thread

      thread ->
        thread
    end
  end

  # One live session per thread (no ended_at) so the roster shows it IN FLIGHT. pane_ref stays nil
  # until you point it at a real tmux pane — the center then shows a placeholder, honestly.
  defp ensure_session(thread, agent) do
    if is_nil(Staff.session_for_thread(thread)) do
      Staff.start_session(%{agent_id: agent.id, thread_id: thread.id})
    end
  end

  defp seed_chatter(thread, lead) do
    if Channel.thread_messages(thread) == [] do
      post(thread, lead, "picking this up")
      post(thread, "you", "thanks — ping me if you get blocked")
      post(thread, lead, "will do")
    end
  end

  # Best-effort brief material (LEARNINGS / BLOCKERS / SHIPPED). Wrapped so an unknown required
  # field can't abort the seed — the dossier just shows fewer sections.
  defp seed_brief(thread, lead) do
    # Idempotent: only seed brief material once (a fresh thread has no facts yet).
    if Dossier.facts_for_thread(thread) == [], do: do_seed_brief(thread, lead)
  end

  defp do_seed_brief(thread, lead) do
    safe(fn ->
      Dossier.bank_fact(%{
        thread_id: thread.id,
        kind: "learned",
        text: "raxol_terminal renders the board",
        provenance: "stated"
      })
    end)

    safe(fn ->
      Dossier.raise_issue(%{
        thread_id: thread.id,
        summary: "center tmux embed still pending",
        found_by: lead
      })
    end)

    safe(fn ->
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "work_landed",
        detail: %{"summary" => "the read-only render path"}
      })
    end)
  end

  defp post(thread, author, body) do
    Channel.post(%{thread_id: thread.id, author: author, body: body})
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> :ok
  end
end
