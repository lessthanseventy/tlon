defmodule Server.MCP.Tokens do
  @moduledoc """
  The identity seam of the sovereign channel (pi doc §2a). A token binds an MCP connection to its
  (thread, agent) so every tool reads identity from the connection's claims, never from a call
  parameter — banking onto the wrong thread is unrepresentable rather than merely discouraged.

  **STATELESS and restart-surviving.** A token IS its claims: an HMAC over
  `(thread_id, agent_id, agent)` signed with the per-world key (`Server.MCP.Secret`). `resolve/1`
  verifies the signature and decodes — no in-memory registry, so a token stays valid across a node
  restart, which matters on the **aleph dogfood hub**: it restarts constantly during development,
  and a registry-backed token would 401 every spawned session on each restart.

  A stale grant that outlives its session is the zombie problem wearing a lanyard — handled by the
  SESSION model, not the token lifetime: `resolve` attaches the CURRENT live session for (thread,
  agent) via `Staff.live_session/2`, and the partial unique index guarantees at most one. So a
  token from a dead session resolves to whoever is live now (or to no session), never resurrects a
  zombie. Forgery is out of scope on a single-human loopback machine (§8: how a machine
  authenticates is local configuration), and the HMAC still means only a holder of the world's key
  can mint.
  """
  alias Server.Agent
  alias Server.MCP.Secret
  alias Server.Staff
  alias Server.Thread

  @type binding :: %{
          thread_id: integer(),
          agent_id: integer(),
          agent: String.t(),
          session_id: integer() | nil
        }

  @doc "Mint a signed token binding (thread, agent). Survives a node restart (same world key)."
  @spec mint(Thread.t(), Agent.t()) :: String.t()
  def mint(%Thread{id: thread_id}, %Agent{id: agent_id, name: name}) do
    payload = encode(%{"t" => thread_id, "a" => agent_id, "n" => name})
    payload <> "." <> sign(payload)
  end

  @doc """
  The binding behind a token, or `:error` for one this world's key never signed (a forgery, a
  wrong-world token, or a garbled string). `session_id` is the CURRENT live session for the pair,
  resolved at read time — nil before `register`, and never a stale session after.
  """
  @spec resolve(String.t()) :: {:ok, binding()} | :error
  def resolve(token) when is_binary(token) do
    with [payload, sig] <- String.split(token, ".", parts: 2),
         true <- valid?(sig, payload),
         {:ok, %{"t" => thread_id, "a" => agent_id, "n" => name}} <- decode(payload) do
      {:ok,
       %{
         thread_id: thread_id,
         agent_id: agent_id,
         agent: name,
         session_id: live_session_id(thread_id, agent_id)
       }}
    else
      _ -> :error
    end
  end

  defp sign(payload) do
    :hmac |> :crypto.mac(:sha256, Secret.get(), payload) |> Base.url_encode64(padding: false)
  end

  # Constant-time compare of the presented signature against the recomputed one.
  defp valid?(sig, payload), do: byte_size(sig) == byte_size(sign(payload)) and secure_equal?(sig, sign(payload))

  defp secure_equal?(a, b) do
    :crypto.hash_equals(a, b)
  rescue
    _ -> a == b
  end

  defp encode(map), do: map |> JSON.encode!() |> Base.url_encode64(padding: false)

  defp decode(payload) do
    with {:ok, json} <- Base.url_decode64(payload, padding: false) do
      JSON.decode(json)
    end
  end

  defp live_session_id(thread_id, agent_id) do
    case Staff.live_session(thread_id, agent_id) do
      %{id: id} -> id
      _ -> nil
    end
  end
end
