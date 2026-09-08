defmodule Console.Backend do
  @moduledoc """
  The one door between the cockpit and the server (docs/plans/2026-09-08-one-brain-client-server-plan.md).

  Every server read or write the console makes goes through `call/3`; nothing else in `lib/`
  names a `Server.*` function directly (structs, `Server.Bus` topics and pure helpers excepted).
  The implementation is config: `Console.Backend.Local` applies the function in this node — the
  test env, and hacking on the server with an embedded one — while `Console.Backend.Remote`
  `:erpc`s into the always-up server node (phase 2 of the plan). The facade modules under
  `Console.Server` are what call sites use; they mirror the server's contexts.
  """

  @callback call(module(), atom(), [term()]) :: term()

  @doc "Run `apply(mod, fun, args)` wherever the server lives."
  @spec call(module(), atom(), [term()]) :: term()
  def call(mod, fun, args), do: impl().call(mod, fun, args)

  @doc false
  def impl, do: Application.get_env(:console, :backend, Console.Backend.Local)
end
