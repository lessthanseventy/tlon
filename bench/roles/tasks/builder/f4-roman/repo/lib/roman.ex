defmodule Roman do
  @moduledoc "Roman numerals, for the release names."

  @doc "`{:ok, integer}` for a canonical Roman numeral, else `{:error, :invalid}`."
  def to_integer(_numeral), do: raise("not implemented")
end
