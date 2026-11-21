defmodule Server.Home.Bank.Plaid do
  @moduledoc """
  The read-only door to Plaid for `Server.Home.Source.Bank`. The only calls it can make are the four
  in `paths/0`, all POSTs of JSON to `https://production.plaid.com`; nothing that moves money, reads
  a balance at a price (`/accounts/balance/get`) or asks the bank to refresh.

  The credentials are read at each call and never kept, logged or put in an error: the env
  `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ACCESS_TOKEN`, else the machine secrets
  `$XDG_RUNTIME_DIR/agenix/plaid-client-id`, `plaid-secret`, `plaid-access-token`. An error is
  `{:error, {:plaid, error_code}}` (Plaid's own code, e.g. `"ITEM_LOGIN_REQUIRED"`),
  `{:error, {:http, status}}`, `{:error, {:transport, reason}}` or `{:error, :no_credentials}`.
  Options for a test: `:http` (a function from the URL and the JSON body to
  `{:ok, status, body} | {:error, reason}`), `:client_id`, `:secret`, `:access_token`.
  """

  @host "https://production.plaid.com"
  @paths ~w(/link/token/create /item/public_token/exchange /transactions/sync /accounts/get)
  @days_requested 180
  @client_name "the house"
  @client_user_id "the-house-operator"

  @doc "The Plaid paths this client can call, and no others."
  @spec paths() :: [String.t()]
  def paths, do: @paths

  @doc "A link token for the Link page: the `transactions` product alone, 180 days of history, no redirect URI."
  @spec link_token_create(keyword()) :: {:ok, String.t()} | {:error, term()}
  def link_token_create(opts \\ []) do
    body = %{
      client_name: @client_name,
      language: "en",
      country_codes: ["US"],
      user: %{client_user_id: @client_user_id},
      products: ["transactions"],
      transactions: %{days_requested: @days_requested}
    }

    case post("/link/token/create", body, opts) do
      {:ok, %{"link_token" => token}} when is_binary(token) -> {:ok, token}
      {:ok, _} -> {:error, :unexpected_reply}
      {:error, _} = error -> error
    end
  end

  @doc "The access token a `public_token` from Link is exchanged for."
  @spec exchange_public_token(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def exchange_public_token(public_token, opts \\ []) when is_binary(public_token) do
    case post("/item/public_token/exchange", %{public_token: public_token}, opts) do
      {:ok, %{"access_token" => token}} when is_binary(token) -> {:ok, token}
      {:ok, _} -> {:error, :unexpected_reply}
      {:error, _} = error -> error
    end
  end

  @doc "One page of `/transactions/sync` from `cursor` (nil for the first call), at most `count` changes."
  @spec sync(String.t() | nil, pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync(cursor, count, opts \\ []) do
    body = if cursor in [nil, ""], do: %{count: count}, else: %{count: count, cursor: cursor}
    post("/transactions/sync", body, opts, access_token: true)
  end

  @doc "The accounts with their cached balances (`/accounts/get`, free)."
  @spec accounts(keyword()) :: {:ok, [map()]} | {:error, term()}
  def accounts(opts \\ []) do
    case post("/accounts/get", %{}, opts, access_token: true) do
      {:ok, %{"accounts" => accounts}} when is_list(accounts) -> {:ok, accounts}
      {:ok, _} -> {:error, :unexpected_reply}
      {:error, _} = error -> error
    end
  end

  @doc "The access token, from `opts[:access_token]`, the env or the machine secret; nil when there is none."
  @spec access_token(keyword()) :: String.t() | nil
  def access_token(opts \\ []), do: secret(opts[:access_token], "PLAID_ACCESS_TOKEN", "plaid-access-token")

  defp post(path, body, opts, flags \\ []) when path in @paths do
    with {:ok, client_id} <- credential(opts[:client_id], "PLAID_CLIENT_ID", "plaid-client-id"),
         {:ok, secret} <- credential(opts[:secret], "PLAID_SECRET", "plaid-secret"),
         {:ok, body} <- with_token(body, opts, flags[:access_token]) do
      request = JSON.encode!(Map.merge(body, %{client_id: client_id, secret: secret}))
      http = Keyword.get(opts, :http, &http/2)

      case http.(@host <> path, request) do
        {:ok, 200, reply} -> decode(reply)
        {:ok, status, reply} -> failure(status, reply)
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  defp with_token(body, _opts, nil), do: {:ok, body}

  defp with_token(body, opts, true) do
    case access_token(opts) do
      nil -> {:error, :no_credentials}
      token -> {:ok, Map.put(body, :access_token, token)}
    end
  end

  defp decode(reply) do
    case JSON.decode(reply) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, :unexpected_reply}
    end
  end

  defp failure(status, reply) do
    case JSON.decode(reply) do
      {:ok, %{"error_code" => code}} when is_binary(code) -> {:error, {:plaid, code}}
      _ -> {:error, {:http, status}}
    end
  end

  defp credential(given, env, file) do
    case secret(given, env, file) do
      nil -> {:error, :no_credentials}
      value -> {:ok, value}
    end
  end

  defp secret(given, env, file) do
    with nil <- given,
         nil <- non_empty(System.get_env(env)) do
      from_secret(System.get_env("XDG_RUNTIME_DIR"), file)
    end
  end

  defp from_secret(nil, _file), do: nil

  defp from_secret(dir, file) do
    case File.read(Path.join([dir, "agenix", file])) do
      {:ok, text} -> non_empty(String.trim(text))
      _ -> nil
    end
  end

  defp non_empty(nil), do: nil

  defp non_empty(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  defp http(url, body) do
    _ = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(url), [], ~c"application/json", body},
           [timeout: 30_000, connect_timeout: 5_000, ssl: ssl],
           body_format: :binary
         ) do
      {:ok, {{_v, status, _r}, _headers, reply}} -> {:ok, status, reply}
      {:error, reason} -> {:error, reason}
    end
  end
end
