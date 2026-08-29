defmodule Server.Mentions do
  @moduledoc """
  Parse `@name` handles out of a message body (the addressed-delivery model). Returns
  the raw handles in order of appearance, de-duplicated; the switchboard resolves
  which of them are real agents (an `@here` that names no agent simply wakes no one).
  A handle is `@` followed by a letter and then letters, digits, `_` or `-`, and the
  `@` must not sit inside a word (so `user@Robert` is an address, not a mention).
  """
  @handle ~r/(?<![\p{L}\p{N}_])@([\p{L}][\p{L}\p{N}_-]*)/u

  @spec names(String.t() | nil) :: [String.t()]
  def names(nil), do: []

  def names(body) do
    @handle
    |> Regex.scan(body)
    |> Enum.map(fn [_whole, name] -> name end)
    |> Enum.uniq()
  end
end
