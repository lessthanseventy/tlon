defmodule Server.Repo.Migrations.ThreadRepo do
  @moduledoc false
  use Ecto.Migration

  # A project spans repos; a thread works in ONE of them (its worktree, branch, commits and gates).
  # The path as the project's `repos` list spells it. Nil = the project's first repo.
  def change do
    alter table(:thread) do
      add :repo, :text
    end
  end
end
