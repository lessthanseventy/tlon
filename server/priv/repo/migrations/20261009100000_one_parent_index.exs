defmodule Server.Repo.Migrations.OneParentIndex do
  @moduledoc false
  use Ecto.Migration

  # The one-parent rule was only a changeset check, so two racing links could both pass. The DB now
  # holds it. Rows from before the index may already break the rule: keep each child's earliest
  # parent link and drop the rest, or the index could not be built.
  def up do
    execute """
    DELETE FROM ticket_link l
    USING ticket_link keep
    WHERE l.kind = 'parent' AND keep.kind = 'parent' AND l.to_id = keep.to_id AND keep.id < l.id
    """

    execute "CREATE UNIQUE INDEX ticket_link_one_parent ON ticket_link (to_id) WHERE kind = 'parent'"
  end

  def down, do: execute("DROP INDEX ticket_link_one_parent")
end
