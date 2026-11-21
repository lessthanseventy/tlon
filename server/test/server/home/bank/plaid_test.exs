defmodule Server.Home.Bank.PlaidTest do
  use ExUnit.Case, async: false

  alias Server.Home.Bank.Plaid

  @creds [client_id: "cid-123", secret: "sec-456", access_token: "tok-789"]

  defp stub(reply) do
    test = self()

    fn url, body ->
      send(test, {:request, url, JSON.decode!(body)})
      reply
    end
  end

  defp ok(map), do: {:ok, 200, JSON.encode!(map)}

  setup do
    previous =
      for name <- ~w(PLAID_CLIENT_ID PLAID_SECRET PLAID_ACCESS_TOKEN XDG_RUNTIME_DIR), do: {name, System.get_env(name)}

    for {name, _} <- previous, do: System.delete_env(name)

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)
  end

  test "the client can call four paths and no others" do
    assert Plaid.paths() == ~w(/link/token/create /item/public_token/exchange /transactions/sync /accounts/get)
  end

  test "every call it makes is on that list, a POST of JSON to production" do
    http = stub(ok(%{"link_token" => "lt", "access_token" => "at", "next_cursor" => "c", "accounts" => []}))
    opts = [http: http] ++ @creds

    {:ok, "lt"} = Plaid.link_token_create(opts)
    {:ok, "at"} = Plaid.exchange_public_token("public-1", opts)
    {:ok, _} = Plaid.sync(nil, 500, opts)
    {:ok, []} = Plaid.accounts(opts)

    urls =
      for _ <- 1..4,
          do:
            (
              assert_received {:request, url, _}
              url
            )

    assert Enum.map(urls, &String.replace_prefix(&1, "https://production.plaid.com", "")) == Plaid.paths()
  end

  test "a link token asks for the transactions product alone, 730 days, no redirect" do
    {:ok, _} = Plaid.link_token_create([http: stub(ok(%{"link_token" => "lt"}))] ++ @creds)
    assert_received {:request, _, body}

    assert %{
             "client_id" => "cid-123",
             "secret" => "sec-456",
             "client_name" => "the house",
             "language" => "en",
             "country_codes" => ["US"],
             "products" => ["transactions"],
             "transactions" => %{"days_requested" => 730}
           } = body

    assert %{"client_user_id" => _} = body["user"]
    refute Map.has_key?(body, "redirect_uri")
    refute Map.has_key?(body, "access_token")
  end

  test "sync omits the cursor on the first call and sends it after" do
    http = stub(ok(%{}))
    Plaid.sync(nil, 500, [http: http] ++ @creds)
    assert_received {:request, _, first}
    Plaid.sync("cur-1", 500, [http: http] ++ @creds)
    assert_received {:request, _, second}

    refute Map.has_key?(first, "cursor")
    assert %{"cursor" => "cur-1", "count" => 500, "access_token" => "tok-789"} = second
  end

  test "credentials come from the env, else the machine secrets, trimmed" do
    dir = Path.join(System.tmp_dir!(), "plaid-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "agenix"))
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join([dir, "agenix", "plaid-client-id"]), "file-cid\n")
    File.write!(Path.join([dir, "agenix", "plaid-secret"]), " file-secret \n")
    File.write!(Path.join([dir, "agenix", "plaid-access-token"]), "file-token\n")
    System.put_env("XDG_RUNTIME_DIR", dir)

    {:ok, _} = Plaid.sync(nil, 1, http: stub(ok(%{})))

    assert_received {:request, _,
                     %{"client_id" => "file-cid", "secret" => "file-secret", "access_token" => "file-token"}}

    System.put_env("PLAID_ACCESS_TOKEN", "env-token")
    assert Plaid.access_token() == "env-token"
  end

  test "no credentials is an error and nothing is sent" do
    System.put_env(
      "XDG_RUNTIME_DIR",
      System.tmp_dir!() <> "/plaid-none-#{System.pid()}-#{System.unique_integer([:positive])}"
    )

    assert Plaid.access_token() == nil
    assert {:error, :no_credentials} = Plaid.accounts(http: stub(ok(%{})))
    refute_received {:request, _, _}
  end

  test "an error keeps Plaid's error_code and never the secret" do
    reply = {:ok, 400, JSON.encode!(%{"error_code" => "ITEM_LOGIN_REQUIRED", "error_message" => "sec-456"})}
    assert {:error, {:plaid, "ITEM_LOGIN_REQUIRED"}} = Plaid.sync(nil, 1, [http: stub(reply)] ++ @creds)
    assert {:error, {:http, 502}} = Plaid.sync(nil, 1, [http: stub({:ok, 502, "<html>"})] ++ @creds)
    assert {:error, {:transport, :timeout}} = Plaid.sync(nil, 1, [http: stub({:error, :timeout})] ++ @creds)
    assert {:error, :unexpected_reply} = Plaid.accounts([http: stub(ok(%{"nope" => 1}))] ++ @creds)

    for {:error, reason} <- [Plaid.sync(nil, 1, [http: stub(reply)] ++ @creds)],
        do: refute(inspect(reason) =~ "sec-456")
  end
end
