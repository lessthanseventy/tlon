defmodule Mix.Tasks.Server.BankLink do
  @shortdoc "Link the bank to the home through Plaid, once (read-only)"
  @moduledoc """
  #{@shortdoc}. Serves a page on the loopback, prints its address, and prints the access token once
  when the bank login is done (`Server.Home.Bank.Link`). Refuses when an access token is already
  present: the Plaid account allows ten links for ever. `--allow-another-link` links anyway.
  Needs `PLAID_CLIENT_ID` and `PLAID_SECRET` (or the machine secrets `plaid-client-id`, `plaid-secret`).
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Home.Bank.Link

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [allow_another_link: :boolean])
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started([:inets, :ssl, :bandit])

    case Link.run(force: opts[:allow_another_link] == true) do
      {:ok, _token} ->
        :ok

      {:error, :already_linked} ->
        Mix.raise(
          "an access token is already present. The Plaid account allows ten links for ever; " <>
            "to link again on purpose, run: mise run home:bank:link -- --allow-another-link"
        )

      {:error, reason} ->
        Mix.raise("the bank was not linked: #{inspect(reason)}")
    end
  end
end
