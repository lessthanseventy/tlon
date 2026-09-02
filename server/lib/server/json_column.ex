defmodule Server.JSONColumn do
  @moduledoc """
  An Ecto type for a JSON column: a map or list in Elixir, a JSON string in SQLite
  TEXT, encoded with the stdlib `JSON` module (the same one `Server.Doctor` exports
  with). Used for `event.detail` — "a JSON detail only for what a human reads" (§4) —
  and for `workspace`'s `paths`/`roster` (JSON arrays) / `knobs` (object). Never queried;
  in `sqlite3` at 2am it reads as plain JSON text.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(map) when is_map(map), do: {:ok, map}
  def cast(list) when is_list(list), do: {:ok, list}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(json) when is_binary(json), do: {:ok, JSON.decode!(json)}

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(map) when is_map(map), do: {:ok, JSON.encode!(map)}
  def dump(list) when is_list(list), do: {:ok, JSON.encode!(list)}
  def dump(_), do: :error
end
