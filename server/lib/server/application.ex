defmodule Server.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # PubSub is always up — it is the switchboard's nudge and cheap to run, and the
    # test harness needs it so Channel.post can broadcast. The Repo is started
    # except under :test (the harness owns its lifecycle). The switchboard Server is
    # opt-in (off by default): its presence-gating prerequisite exists (BOTH
    # warmth and engine-credit, see Server.Switchboard), but the wake only pokes for
    # real once a deployment ALSO sets a non-Inert arbiter — so the dogfood hub
    # (console, topology A) flips :start_switchboard on, the prod service stays inert
    # until the service→tmux path is proven (see the tlön design doc). The MCP
    # channel is opt-in the same way: a node that serves agents flips :start_mcp on.
    # The consult mirror is on by default (it only writes DB rows, never pokes a pane, so it
    # is safe where the switchboard is deliberately opt-in) — but the test harness turns it
    # off so the pure maybe_mirror tests don't double-fire.
    # Boot integrity (reshape slice A): seed the default workspace if none, repair
    # dangling thread→workspace refs. Replaces the flake's ExecStartPre seed_workspace.
    # Server.Bootstrap's start_link runs the work synchronously and returns :ignore,
    # so children after it (consult mirror, MCP/Bandit) start only once seed+repair
    # are done — nothing serves against an unseeded db.
    children =
      [
        {Phoenix.PubSub, name: Server.PubSub},
        # Fire-and-forget best-effort work off the request path — today the embed-on-write embedder
        # (Server.Recall.embed_on_write): a crash or a slow ollama stays here, off bank_fact.
        {Task.Supervisor, name: Server.TaskSupervisor},
        # Explicit thinking/idle declarations (in-memory liveness; harnesses re-declare after a restart).
        Server.Presence.Thinking
      ] ++
        maybe(:start_repo, true, Server.Repo) ++
        maybe(:bootstrap, true, Server.Bootstrap) ++
        maybe(:start_consult_mirror, true, Server.Consult.Mirror) ++
        maybe(:start_switchboard, false, Server.Switchboard.Runner) ++
        maybe(:start_mcp, false, mcp_children()) ++
        maybe(:memory_pass, false, {Server.Memory.TurnPass, []}) ++
        maybe(:maintain, false, {Server.Maintain.Monitor, []})

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  defp maybe(key, default, children) do
    if Application.get_env(:server, key, default), do: List.wrap(children), else: []
  end

  # The sovereign channel (pi doc §2a): the token registry, the MCP server, and
  # Bandit serving its plug — LOOPBACK ONLY: a listener on a personal machine
  # binds no further than the machine.
  defp mcp_children do
    [
      # Server.MCP.Tokens is stateless (signed tokens, no registry) — nothing to supervise.
      {Server.MCP.Endpoint, transport: :streamable_http},
      # The Gateway routes POST /mint (a fresh-token mint for an adapter's per-connect auth)
      # and forwards everything else to the anubis MCP transport. Loopback only — a personal
      # machine binds no further than 127.0.0.1. See Server.MCP.Gateway for why /mint exists.
      {Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: Application.get_env(:server, :mcp_port, 4040)}
    ]
  end
end
