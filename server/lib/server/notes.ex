defmodule Server.Notes do
  @moduledoc """
  The notes context (2026-08-30): funes-native scratch. Write pipe + scoped reads over the
  `note` table; agents and the operator both write here (MCP `write_note`/`get_notes`), and
  the same rows feed recall. Every write announces on `Server.Bus`'s notes topic so a live
  Notes surface refreshes.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Note
  alias Server.Repo

  @doc "Write a note. `{:ok, note}` or `{:error, changeset}` (missing body / bad scope / scope_id mismatch)."
  def write(attrs) do
    attrs |> Note.write_changeset() |> Repo.insert() |> Bus.announce(:note_written)
  end

  @doc ~s{Notes in a scope, newest-first. `for_scope("global", nil)` / `for_scope("project", id)`.}
  def for_scope(scope, scope_id) do
    Repo.all(from n in Note, where: ^where_scope(scope, scope_id), order_by: [desc: n.id])
  end

  # The whole where as ONE dynamic (Ecto forbids `and`-ing a dynamic inline): `scope_id IS NULL`
  # for global, `= ^id` otherwise.
  defp where_scope(scope, nil), do: dynamic([n], n.scope == ^scope and is_nil(n.scope_id))
  defp where_scope(scope, id), do: dynamic([n], n.scope == ^scope and n.scope_id == ^id)

  @doc "A note by id, or nil."
  def get(id), do: Repo.get(Note, id)

  @doc "Edit a note's body. `{:ok, note}` or `{:error, changeset}`."
  def edit(%Note{} = note, attrs) do
    note |> Note.edit_changeset(attrs) |> Repo.update() |> Bus.announce(:note_edited)
  end

  @doc "Remove a note."
  def remove(%Note{} = note) do
    note |> Repo.delete() |> Bus.announce(:note_removed)
  end
end
