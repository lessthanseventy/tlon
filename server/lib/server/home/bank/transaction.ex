defmodule Server.Home.Bank.Transaction do
  @moduledoc """
  One bank transaction as Plaid reported it (`home_bank_transactions`), keyed by Plaid's
  `transaction_id`. `amount_cents` keeps Plaid's sign: positive is money out.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:transaction_id, :string, autogenerate: false}
  schema "home_bank_transactions" do
    field :account_id, :string
    field :date, :date
    field :amount_cents, :integer
    field :name, :string
    field :merchant_name, :string
    field :pending, :boolean, default: false
  end
end
