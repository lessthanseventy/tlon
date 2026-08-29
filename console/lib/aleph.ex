defmodule Console do
  @moduledoc """
  The boundary of the cockpit (enforced by the `:boundary` compiler, same as funes'). One
  coarse boundary: aleph's internal layering is house-rule territory (pure decisions, thin
  edges), but its reach INTO funes is load-bearing — `deps: [Server]` means aleph may call only
  what `Server` exports, and a new reach into funes internals fails `mise run check` instead of
  silently widening the surface.
  """

  use Boundary, deps: [Server], exports: []
end
