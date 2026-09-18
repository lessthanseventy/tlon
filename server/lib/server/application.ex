defmodule Server.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # PubSub is always up — it is the switchboard's nudge and cheap to run, and the
    # test harness needs it so Channel.post can broadcast. The Repo is started
    # except under :test (the harness owns its lifecycle). The switchboard runner is
    # opt-in per node (:start_switchboard — the console's config, the service's
    # TLON_START_SWITCHBOARD): with an arbiter it pokes panes, without one it is
    # bookkeeping only (drain on boot, claim, coalesce). The MCP channel is opt-in the
    # same way: a node that serves agents flips :start_mcp on. The consult mirror is on
    # by default (it only writes DB rows) — the test harness turns it off so the pure
    # maybe_mirror tests don't double-fire.
    # Boot integrity: Server.Bootstrap seeds the default workspace if none and repairs
    # dangling thread→workspace refs; its start_link runs the work synchronously and
    # returns :ignore, so children after it (consult mirror, MCP/Bandit) start only once
    # seed+repair are done — nothing serves against an unseeded db.
    # One-brain E: Oban on the store's Postgres (cron drain, later the sweeps); D: the web UI's
    # own Bandit listener. Both opt-in per node like MCP — the service flips them on.
    # get_env, not fetch_env!: a root app that embeds :server (the console) never evaluates this
    # app's config.exs, and the child list is built before the flag is consulted
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
        maybe(:maintain, false, {Server.Maintain.Monitor, []}) ++
        maybe(:start_oban, false, {Oban, Application.get_env(:server, Oban, [])}) ++
        maybe(:start_web, false, Server.Web.Endpoint)

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
      # `start: true` is explicit: without it anubis asks "is a Phoenix HTTP server running?" and,
      # since the web endpoint (piece D) exists with its own listener flag, would answer no and
      # return :ignore — the MCP channel then 500s on every request (2026-09-18).
      {Server.MCP.Endpoint, transport: {:streamable_http, start: true}},
      # The Gateway routes POST /mint (a fresh-token mint for an adapter's per-connect auth)
      # and forwards everything else to the anubis MCP transport. Loopback only — a personal
      # machine binds no further than 127.0.0.1. See Server.MCP.Gateway for why /mint exists.
      {Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: Application.get_env(:server, :mcp_port, 4040)}
    ]
  end
end
