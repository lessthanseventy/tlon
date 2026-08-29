defmodule Server.Presence.Engine do
  @moduledoc """
  The engine-credit half of presence (§3b) — the OTHER "clocked out": a session
  whose model is out of credits or past its rate-limit window. Warmth (`Server.Presence`)
  asks "is the context still cheap to resume?"; this asks "can the model behind it take
  a turn at all right now?". Both gate the wake; a poke that clears neither burns a paid
  turn for nothing.

  A **capability, not a product** — symmetric with `Server.Arbiter`. §8 forbids the design
  from naming a vendor, so which engine is spent (Claude's five-hour window, an ollama
  flat plan that never is) lives entirely in the backend, chosen by config
  `:server, :engine_presence`, defaulting to `Available` — absent config, every engine is
  available, so the wake is gated on warmth alone (degrade honestly). The
  switchboard's `recipients/1` excludes a session whose engine is clocked out.
  """
  @callback clocked_out?(agent :: Server.Agent.t()) :: boolean()

  @doc "The configured engine-presence backend (defaults to the always-available one)."
  def impl, do: Application.get_env(:server, :engine_presence, Server.Presence.Engine.Available)

  @doc "Is this agent's engine clocked out right now, per the configured backend?"
  def clocked_out?(agent), do: impl().clocked_out?(agent)
end

defmodule Server.Presence.Engine.Available do
  @moduledoc """
  The default engine-presence backend: nothing is ever clocked out. A machine that has
  not wired a credit/rate-limit signal still runs the whole design — the wake is gated on
  warmth alone. Local models are first-class (§8), and a flat-plan
  engine that never clocks out is precisely this.
  """
  @behaviour Server.Presence.Engine

  @impl true
  def clocked_out?(_agent), do: false
end

defmodule Server.Presence.Engine.Manual do
  @moduledoc """
  A HAND toggle — the concrete backend the dogfood hub runs. An engine is clocked out iff the
  operator has marked it so: it is in `Server.Presence.clocked_out_engines/0` (the app-env set,
  flipped by `Server.Presence.clock_out/1` / `clock_in/1`). No vendor is named or polled (§8) —
  when the scarce Claude window is spent, the operator flips it from `funes:console` and the
  switchboard stops poking Claude sessions; a real rate-limit reader is a later, local backend
  swapped in the same seam. Tests drive it the same way (`put_env :clocked_out_engines`).
  """
  @behaviour Server.Presence.Engine

  @impl true
  def clocked_out?(%{engine: engine}), do: engine in Server.Presence.clocked_out_engines()
end
