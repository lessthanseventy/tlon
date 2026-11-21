defmodule Server.Home.Bank.Link do
  @moduledoc """
  The one-time link of the bank (`mise run home:bank:link`). It makes a link token
  (`Server.Home.Bank.Plaid.link_token_create/1`), serves a plain page on the loopback that opens
  Plaid Link with it (the login happens on the bank's own site), takes the `public_token` Link hands
  back on a nonce-guarded path of the same loopback server, exchanges it, and says the access token
  and what to do with it once: it is never written anywhere. A token already present (env or machine
  secret) refuses the run, because the Plaid account allows ten links for ever; `force: true` is the
  deliberate override. Options: `:say` (a one-argument printer), `:port` (default a free one),
  `:timeout_ms`, and the client's.
  """
  @behaviour Plug

  import Plug.Conn

  alias Server.Home.Bank.Plaid

  @timeout_ms 30 * 60_000
  @script "https://cdn.plaid.com/link/v2/stable/link-initialize.js"

  @doc """
  Run the link: `{:ok, access_token}` once the bank is linked, or `{:error, reason}`
  (`:already_linked`, a Plaid error, `:timeout`).
  """
  @spec run(keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(opts \\ []) do
    say = Keyword.get(opts, :say, &IO.puts/1)

    with :ok <- unlinked(opts),
         {:ok, link_token} <- Plaid.link_token_create(opts) do
      nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      plug = {__MODULE__, %{owner: self(), link_token: link_token, nonce: nonce}}

      {:ok, server} =
        Bandit.start_link(plug: plug, ip: {127, 0, 0, 1}, port: Keyword.get(opts, :port, 0), startup_log: false)

      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      say.("Open http://localhost:#{port}/ in your browser and follow the page. Waiting for the bank login...")

      result = finish(nonce, opts)
      Supervisor.stop(server)
      announce(result, say)
    end
  end

  defp unlinked(opts) do
    if Plaid.access_token(opts) != nil and opts[:force] != true, do: {:error, :already_linked}, else: :ok
  end

  defp finish(nonce, opts) do
    receive do
      {:public_token, ^nonce, public_token} -> Plaid.exchange_public_token(public_token, opts)
    after
      Keyword.get(opts, :timeout_ms, @timeout_ms) -> {:error, :timeout}
    end
  end

  defp announce({:ok, token} = ok, say) do
    say.("""

    Linked. The access token, shown once and kept nowhere:

      #{token}

    Next:
      cd ~/projects/ficciones/secrets && agenix -e plaid-access-token.age   # paste the token as the whole file
      git add plaid-access-token.age
      home:switch
    """)

    ok
  end

  defp announce(error, _say), do: error

  @impl true
  def init(config), do: config

  @impl true
  def call(%{method: "GET", request_path: "/"} = conn, %{link_token: link_token, nonce: nonce}),
    do: conn |> put_resp_content_type("text/html") |> send_resp(200, page(link_token, nonce))

  def call(%{method: "POST", request_path: "/callback/" <> given} = conn, %{owner: owner, nonce: nonce}) do
    with true <- Plug.Crypto.secure_compare(given, nonce),
         {:ok, body, conn} <- read_body(conn, length: 10_000),
         {:ok, %{"public_token" => public_token}} when is_binary(public_token) <- JSON.decode(body) do
      send(owner, {:public_token, nonce, public_token})
      send_resp(conn, 200, "ok")
    else
      _ -> send_resp(conn, 400, "refused")
    end
  end

  def call(conn, _config), do: send_resp(conn, 404, "not found")

  @doc "The page: what it is about to do, a button, and Link opened with `link_token`, answering `nonce`."
  @spec page(String.t(), String.t()) :: String.t()
  def page(link_token, nonce) do
    token = link_token |> JSON.encode!() |> String.replace("</", "<\\/")

    """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>Link the bank</title></head>
    <body style="font-family: sans-serif; max-width: 32rem; margin: 3rem auto">
    <h1>Link the bank</h1>
    <p>The house will read your transactions and balances, read-only. It cannot move money.</p>
    <p>You log in on Chime's own site; the house never sees the password.</p>
    <button id="go" style="font-size: 1.2rem; padding: .5rem 1rem">Link the bank</button>
    <p id="status"></p>
    <script src="#{@script}"></script>
    <script>
    const status = (text) => { document.getElementById("status").textContent = text };
    const handler = Plaid.create({
      token: #{token},
      onSuccess: (publicToken) => {
        fetch("/callback/#{nonce}", { method: "POST", body: JSON.stringify({ public_token: publicToken }) })
          .then((r) => status(r.ok ? "Linked. Go back to the terminal." : "The house refused it; see the terminal."))
          .catch(() => status("Could not reach the house; see the terminal."));
      },
      onExit: (err) => status(err ? "Link stopped: " + err.error_code : "Link closed."),
    });
    document.getElementById("go").onclick = () => handler.open();
    </script>
    </body></html>
    """
  end
end
