defmodule Console do
  @moduledoc """
  The boundary of the cockpit (enforced by the `:boundary` compiler, same as server'). One
  coarse boundary: console's internal layering is house-rule territory (pure decisions, thin
  edges), but its reach INTO server is load-bearing — `deps: [Server]` means console may call only
  what `Server` exports, and a new reach into server internals fails `mise run check` instead of
  silently widening the surface.
  """

  use Boundary, deps: [Server], exports: []
end
