defmodule Duration do
  @moduledoc "Schedule durations like `1h30m`."

  @doc "`{:ok, seconds}` for a duration string, or `{:error, reason}`."
  def parse(_string), do: raise("not implemented")
end
