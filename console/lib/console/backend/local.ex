defmodule Console.Backend.Local do
  @moduledoc "The server is in this node: the embedded `:server` app (tests, `server:dev`)."
  @behaviour Console.Backend

  @impl true
  def call(mod, fun, args), do: apply(mod, fun, args)
end
