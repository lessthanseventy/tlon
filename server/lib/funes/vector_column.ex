defmodule Server.VectorColumn do
  @moduledoc """
  An Ecto type for an embedding vector: a list of floats in Elixir, a JSON array in SQLite TEXT
  (stdlib `JSON`). The sibling of `Server.JSONColumn` for the one thing that column can't hold — a
  bare list. Used for `fact.embedding`; it is read for cosine at recall, never SQL-queried.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(list) when is_list(list), do: {:ok, list}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(json) when is_binary(json), do: {:ok, JSON.decode!(json)}

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(list) when is_list(list), do: {:ok, JSON.encode!(list)}
  def dump(_), do: :error
end
