defmodule Server.Presence do
  @moduledoc """
  Warmth — presence's concrete half (console §3b), in one home so the switchboard and
  the roster share one definition instead of drifting. A session is **warm** (cheap
  to resume) only while its context is still in the prompt cache (~1h,
  `:warmth_window_seconds`); past that it is **cold** and must not be woken, or a
  poke pays a full transcript re-ingestion. The switchboard won't wake a cold
  session; the IN FLIGHT roster shows who is on the clock. The engine-credit half of
  "clocked out" (spent credits / rate-limit window) is `Server.Presence.Engine`, a
  pluggable backend surfaced here through `clocked_out?/1` so presence stays one home.
  """
  alias Server.Presence.Engine

  @default_warmth_seconds 3600

  @doc "The configured warmth window in seconds."
  def warmth_window, do: Application.get_env(:server, :warmth_window_seconds, @default_warmth_seconds)

  @doc "The instant before which a `last_active_at` is cold. Pass `now` for testable time."
  def warmth_cutoff(now \\ now()), do: DateTime.shift(now, second: -warmth_window())

  @doc "Is a session (or a bare `last_active_at`) warm as of `now`?"
  def warm?(session_or_time, now \\ now())
  def warm?(%{last_active_at: at}, now), do: warm?(at, now)
  def warm?(nil, _now), do: false
  def warm?(%DateTime{} = at, now), do: DateTime.after?(at, warmth_cutoff(now))

  @doc """
  The engine-credit half (§3b): is this agent's engine clocked out right now, per the
  configured `Server.Presence.Engine` backend? The switchboard's `recipients/1` excludes a
  session whose engine this reports spent.
  """
  def clocked_out?(agent), do: Engine.clocked_out?(agent)

  @doc "The engine handles the operator has manually marked clocked-out (the `Manual` backend's store)."
  def clocked_out_engines, do: Application.get_env(:server, :clocked_out_engines, [])

  @doc "Mark `engine` clocked out — the switchboard stops poking its sessions until `clock_in/1`."
  def clock_out(engine),
    do: Application.put_env(:server, :clocked_out_engines, Enum.uniq([engine | clocked_out_engines()]))

  @doc "Mark `engine` available again — its window refreshed, credits back."
  def clock_in(engine), do: Application.put_env(:server, :clocked_out_engines, clocked_out_engines() -- [engine])

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
