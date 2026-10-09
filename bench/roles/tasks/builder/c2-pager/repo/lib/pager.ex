defmodule Pager do
  @moduledoc "Pages over a list. Pages are numbered from 1."

  @doc "The items on page `page` of `items`, `size` to a page; `[]` past the end."
  def page(items, page, size) when page >= 1 and size >= 1 do
    Enum.slice(items, page * size, size)
  end

  @doc "How many pages `items` fills at `size` to a page (0 for none)."
  def count(items, size) when size >= 1, do: div(length(items), size)
end
