defmodule Server.NoteRevision do
  @moduledoc """
  A body a note had before an edit replaced it, stamped with when it was written (the note's
  `updated_at` then). Kept for the dump (`Server.Life.put_dump/3`): a page poured out over weeks
  is never one bad save from gone.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "note_revision" do
    field :body, :string
    field :created_at, :utc_datetime
    belongs_to :note, Server.Note
  end
end
