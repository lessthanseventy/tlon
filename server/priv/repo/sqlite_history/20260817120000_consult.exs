defmodule Server.Repo.Migrations.Consult do
  @moduledoc false
  use Ecto.Migration

  # The agent-to-agent consult (docs/plans/2026-08-17-agent-peer-consult-design.md):
  # a correlated ask/answer pair between two agents on different threads. Three columns
  # on `message` carry it:
  #
  #   * `consult_id`       — the correlation id linking the ask and every mirrored reply.
  #   * `origin_thread_id` — the asker's thread, where the answer is mirrored back.
  #   * `mirrored`         — the echo-guard marker: a mirrored copy is never re-mirrored,
  #                          so ask→mirror→mirror-of-mirror→… cannot loop.
  #
  # All three are NULL/0 for an ordinary message; only funes' Consult context sets them.
  def change do
    alter table(:message) do
      add :consult_id, :integer
      add :origin_thread_id, :integer
      add :mirrored, :boolean, default: false, null: false
    end
  end
end
