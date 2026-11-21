defmodule Server.Home.Bank.LinkTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias Server.Home.Bank.Link
  alias Server.Home.Bank.Plaid

  @creds [client_id: "cid", secret: "sec"]

  setup do
    previous = for name <- ~w(PLAID_ACCESS_TOKEN XDG_RUNTIME_DIR), do: {name, System.get_env(name)}
    for {name, _} <- previous, do: System.delete_env(name)

    System.put_env(
      "XDG_RUNTIME_DIR",
      System.tmp_dir!() <> "/no-secrets-#{System.pid()}-#{System.unique_integer([:positive])}"
    )

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)
  end

  defp stub do
    test = self()

    fn url, body ->
      send(test, {:request, URI.parse(url).path, JSON.decode!(body)})

      case URI.parse(url).path do
        "/link/token/create" -> {:ok, 200, JSON.encode!(%{"link_token" => "link-sandbox-abc"})}
        "/item/public_token/exchange" -> {:ok, 200, JSON.encode!(%{"access_token" => "access-123"})}
      end
    end
  end

  defp call(conn), do: Link.call(conn, %{owner: self(), link_token: "link-abc", nonce: "n0nce"})

  test "an access token already present refuses the link, and nothing is asked of Plaid" do
    System.put_env("PLAID_ACCESS_TOKEN", "already")
    assert {:error, :already_linked} = Link.run([http: stub(), say: fn _ -> :ok end] ++ @creds)
    refute_received {:request, _, _}
  end

  test "the page says what it does, loads Plaid's Link with the token, and answers on the nonce path" do
    conn = call(conn(:get, "/"))
    assert conn.status == 200
    assert conn.resp_body =~ "https://cdn.plaid.com/link/v2/stable/link-initialize.js"
    assert conn.resp_body =~ ~s("link-abc")
    assert conn.resp_body =~ "/callback/n0nce"
    assert conn.resp_body =~ "read-only"
    assert conn.resp_body =~ "Chime's own site"
  end

  test "a link token cannot close the script tag it is written in" do
    assert Link.page("</script><script>alert(1)</script>", "n") =~ "<\\/script>"
  end

  test "the callback hands the public token to the owner only on the right nonce" do
    conn = call(conn(:post, "/callback/n0nce", JSON.encode!(%{public_token: "public-1"})))
    assert conn.status == 200
    assert_received {:public_token, "n0nce", "public-1"}

    assert call(conn(:post, "/callback/wrong", JSON.encode!(%{public_token: "public-2"}))).status == 400
    assert call(conn(:post, "/callback/n0nce", "not json")).status == 400
    assert call(conn(:post, "/callback/n0nce", JSON.encode!(%{public_token: 7}))).status == 400
    assert call(conn(:get, "/elsewhere")).status == 404
    refute_received {:public_token, _, _}
  end

  test "the whole flow on the loopback: page, callback, exchange, the token said once" do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
    test = self()
    http = stub()
    run = Task.async(fn -> Link.run([http: http, say: &send(test, {:said, &1})] ++ @creds) end)

    assert_receive {:said, "Open http://localhost:" <> rest}, 5_000
    {port, _} = Integer.parse(rest)
    base = ~c"http://127.0.0.1:#{port}"

    {:ok, {{_, 200, _}, _, page}} = :httpc.request(:get, {base ++ ~c"/", []}, [], body_format: :binary)
    [_, nonce] = Regex.run(~r{/callback/([\w-]+)}, page)

    body = JSON.encode!(%{public_token: "public-1"})

    {:ok, {{_, 200, _}, _, _}} =
      :httpc.request(:post, {base ++ ~c"/callback/#{nonce}", [], ~c"application/json", body}, [], [])

    assert {:ok, "access-123"} = Task.await(run, 5_000)
    assert_received {:request, "/link/token/create", %{"products" => ["transactions"]}}
    assert_received {:request, "/item/public_token/exchange", %{"public_token" => "public-1"}}

    assert_received {:said, said}
    assert said =~ "access-123"
    assert said =~ "cd ~/projects/ficciones/secrets && agenix -e plaid-access-token.age"
    assert said =~ "git add plaid-access-token.age"
    assert said =~ "home:switch"
    refute_received {:said, _}
    assert {:error, _} = :httpc.request(:get, {base ++ ~c"/", []}, [], [])
  end

  test "a link that is never finished times out and says nothing of a token" do
    assert {:error, :timeout} = Link.run([http: stub(), say: fn _ -> :ok end, timeout_ms: 50] ++ @creds)
  end

  test "--allow-another-link is the one way past a present token" do
    System.put_env("PLAID_ACCESS_TOKEN", "already")
    assert {:error, :timeout} = Link.run([http: stub(), say: fn _ -> :ok end, timeout_ms: 50, force: true] ++ @creds)
    assert Plaid.access_token() == "already"
  end
end
