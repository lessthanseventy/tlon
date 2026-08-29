defmodule Server.Repo.Migrations.RenameWorkspaceRefToPaneRef do
  use Ecto.Migration

  # 006 rename session.workspace_ref → session.pane_ref (aleph design §7). The
  # column was named for Herdr's noun ("workspace") back when it pointed into Herdr;
  # Herdr is gone and the ref now points at a tmux PANE, so the name was lying. The
  # field stays exactly what it was — §2's one OPAQUE seam — only its name changes to
  # match its target (a reference is named for what it points at, never for the tool
  # that used to own it). The original CREATE TABLE migration is applied history and
  # is left untouched; this is the forward-only rename.
  #
  # SQLite has ALTER TABLE ... RENAME COLUMN since 3.25 (2018), which ecto_sqlite3
  # drives — no table rebuild.
  def change do
    rename table(:session), :workspace_ref, to: :pane_ref
  end
end
