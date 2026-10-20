defmodule Server.Repo.Migrations.TicketIssueSeen do
  @moduledoc false
  use Ecto.Migration

  # How many times a ticket's or an issue's fault has been seen: a recurrence bumps it instead of
  # filing it again (`Server.Recurrence`).
  def change do
    alter table(:ticket), do: add(:seen, :integer, null: false, default: 1)
    alter table(:issue), do: add(:seen, :integer, null: false, default: 1)
  end
end
