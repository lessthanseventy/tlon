defmodule Server.MCP.TokenValidator do
  @moduledoc """
  Resolves a bearer token against `Server.MCP.Tokens` — the whole authorization
  model on a single-human machine: a token this node minted, or 401. The claims
  carry the binding (thread, agent, session) every tool reads from its frame,
  plus the token itself so `register` can bind its session back here. `aud`
  mirrors the configured resource because anubis validates audience
  unconditionally; there is no `exp` — validity rests on the HMAC signature
  (`Server.MCP.Tokens`), not a clock.
  """
  @behaviour Anubis.Server.Authorization.Validator

  alias Server.MCP.Tokens

  @impl true
  def validate_token(token, config) do
    case Tokens.resolve(token) do
      {:ok, binding} ->
        {:ok,
         %{
           "sub" => binding.agent,
           "aud" => config.resource,
           "thread_id" => binding.thread_id,
           "agent_id" => binding.agent_id,
           "session_id" => binding.session_id,
           "token" => token
         }}

      :error ->
        {:error, :unknown_token}
    end
  end
end
