defmodule Server.Repo.Migrations.HomeBankTransactions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:home_bank_transactions, primary_key: false) do
      add :transaction_id, :string, primary_key: true
      add :account_id, :string
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :name, :text
      add :merchant_name, :text
      add :pending, :boolean, null: false, default: false
    end

    create index(:home_bank_transactions, [:date])
  end
end
