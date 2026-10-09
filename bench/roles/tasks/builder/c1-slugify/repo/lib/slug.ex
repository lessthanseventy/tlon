defmodule Slug do
  @moduledoc "URL slugs from titles."

  @doc "The URL slug for `title`."
  def slugify(_title), do: raise("not implemented")
end
