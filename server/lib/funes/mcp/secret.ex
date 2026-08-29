defmodule Server.MCP.Secret do
  @moduledoc """
  The per-WORLD signing key for stateless MCP tokens (`Server.MCP.Tokens`). A token is an HMAC over
  its claims, so it must verify across a node restart — which means the key cannot live only in
  memory. It is generated ONCE and persisted in a file beside the world's SQLite db
  (`<database>.token_secret`), so each db is its own trust domain: a token minted for aleph's
  `.dev` world never validates against the always-up service's XDG world, even on one machine.

  Read from `config :server, :token_secret` when set (tests pin a fixed key, no file IO); otherwise
  read-or-create the file, cached in `:persistent_term` so it is hashed off disk once.
  """
  @spec get() :: binary()
  def get do
    case Application.get_env(:server, :token_secret) do
      secret when is_binary(secret) and byte_size(secret) > 0 -> secret
      _ -> cached_file_secret()
    end
  end

  defp cached_file_secret do
    case :persistent_term.get({__MODULE__, :secret}, nil) do
      nil ->
        secret = read_or_create()
        :persistent_term.put({__MODULE__, :secret}, secret)
        secret

      secret ->
        secret
    end
  end

  defp read_or_create do
    path = secret_path()

    case File.read(path) do
      {:ok, data} when byte_size(data) >= 32 ->
        data

      _ ->
        secret = :crypto.strong_rand_bytes(32)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, secret)
        secret
    end
  end

  # Beside the world's db file, so the trust domain is the db. Falls back to a repo-local path if
  # the db path is unset or in-memory (nothing durable to sit beside).
  defp secret_path do
    case Application.get_env(:server, Server.Repo)[:database] do
      db when is_binary(db) and db not in [":memory:", ""] -> db <> ".token_secret"
      _ -> Path.join(System.tmp_dir!(), "tlon.token_secret")
    end
  end
end
