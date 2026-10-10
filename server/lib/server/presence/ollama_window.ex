defmodule Server.Presence.Engine.OllamaWindow do
  @moduledoc """
  The ollama plan's own meter as the engine clock (`Server.Presence.Engine`). A seat whose model
  runs on `ollama-cloud` is clocked out while the plan is spent: a legacy plan's session or weekly
  window at 0% remaining, or a credits plan's allowance at $0, with no purchased credits left. It
  is clocked back in at the spent window's reset. Every other provider is never clocked out here.

  The meter is ollama.com's `/api/balance` (what `mise run ollama:usage` reads), fetched at most
  once a minute. A read that fails clocks nobody out: an unknown meter never stops the office.
  """
  @behaviour Server.Presence.Engine

  import Ecto.Query

  @url ~c"https://ollama.com/api/balance"
  @ttl_s 60
  @cache {__MODULE__, :spent_until}

  @impl true
  def clocked_out?(agent) do
    case cached_until() do
      %DateTime{} = until -> DateTime.before?(DateTime.utc_now(), until) and ollama?(agent)
      nil -> false
    end
  end

  @doc "When a `/api/balance` body's spent window resets, or nil while the plan has room."
  @spec spent_until(binary(), DateTime.t()) :: DateTime.t() | nil
  def spent_until(body, now) do
    case Jason.decode(body) do
      {:ok, %{"included" => included} = balance} when is_map(included) ->
        if !purchased?(balance), do: included |> resets() |> latest_after(now)

      _ ->
        nil
    end
  end

  defp purchased?(%{"purchased" => %{"balance_usd" => usd}}) when is_number(usd), do: usd > 0
  defp purchased?(_balance), do: false

  defp resets(%{"allowance_usd" => _, "balance_usd" => usd, "period" => %{"until" => until}})
       when is_number(usd) and usd <= 0, do: [until]

  defp resets(included) do
    for {window, %{"remaining_percent" => left, "resets_at" => at}} <- included,
        window in ["session", "weekly"],
        is_number(left) and left <= 0,
        do: at
  end

  defp latest_after(stamps, now) do
    stamps
    |> Enum.flat_map(fn at ->
      case DateTime.from_iso8601(at) do
        {:ok, dt, _} -> [dt]
        _ -> []
      end
    end)
    |> Enum.filter(&DateTime.after?(&1, now))
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp cached_until do
    now = System.system_time(:second)

    case :persistent_term.get(@cache, nil) do
      {at, until} when now - at < @ttl_s ->
        until

      _ ->
        until = fetch()
        :persistent_term.put(@cache, {now, until})
        until
    end
  end

  defp fetch do
    with key when is_binary(key) <- key(),
         {:ok, {{_v, 200, _r}, _headers, body}} <-
           :httpc.request(
             :get,
             {@url, [{~c"authorization", ~c"Bearer " ++ String.to_charlist(key)}]},
             [timeout: 5_000, connect_timeout: 5_000, ssl: ssl()],
             body_format: :binary
           ) do
      spent_until(body, DateTime.utc_now())
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp ssl do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  # the env's, else the machine's agenix file (the service's unit carries no secrets)
  defp key do
    case System.get_env("OLLAMA_API_KEY") do
      key when key not in [nil, ""] ->
        key

      _ ->
        with dir when is_binary(dir) <- System.get_env("XDG_RUNTIME_DIR"),
             {:ok, key} <- File.read(Path.join([dir, "agenix", "ollama-api-key"])),
             do: String.trim(key),
             else: (_ -> nil)
    end
  end

  defp ollama?(%{id: id, name: name}) do
    from(wa in Server.WorkspaceAgent, where: wa.agent_id == ^id, select: wa.workspace_id)
    |> Server.Repo.all()
    |> Enum.any?(&(Server.Presence.provider_of(name, &1) == "ollama-cloud"))
  end
end
