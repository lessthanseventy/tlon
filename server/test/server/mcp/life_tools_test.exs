defmodule Server.MCP.LifeToolsTest do
  # The life tools' privacy boundary, over the wire: routines, quests and the status answer to the
  # operator's own sessions and to an assistant seat on a home workspace; every other seat is
  # refused with `not_yours`.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.MCP
  alias Server.Staff
  alias Server.Workspaces

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: {:streamable_http, start: true}})
    bandit = start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    Process.put(:mcp_url, ~c"http://127.0.0.1:#{port}/mcp")

    {:ok, home} =
      Workspaces.register(%{
        name: "Home",
        type: "home",
        roster: [%{archetype: "assistant", name: "ada"}, %{archetype: "builder", name: "hronir"}]
      })

    {:ok, code} = Workspaces.register(%{name: "Code", type: "code", roster: [%{archetype: "builder", name: "revel"}]})
    {:ok, routine} = Server.Life.create_routine(home.id, %{title: "stretch", every: "@daily"})
    {:ok, quest} = Server.Life.create_quest(home.id, %{title: "book the dentist"})
    %{home: home, code: code, routine: routine, quest: quest}
  end

  defp token_for(ws, name) do
    {:ok, thread} = Channel.open_thread(%{title: "#{name}'s desk", workspace_id: ws.id})
    {:ok, thread} = Staff.assign(thread, Staff.agent_by_name(name))
    MCP.Tokens.mint(thread, Staff.agent_by_name(name))
  end

  defp tools(%{home: home, routine: routine, quest: quest}) do
    [
      {"life_status", %{workspace_id: home.id}},
      {"routine_create", %{workspace_id: home.id, title: "walk", every: "@daily"}},
      {"routine_update", %{routine_id: routine.id, title: "stretch more"}},
      {"routine_done", %{routine_id: routine.id}},
      {"quest_create", %{workspace_id: home.id, title: "call mum"}},
      {"quest_done", %{quest_id: quest.id}}
    ]
  end

  test "a builder seat, on the home workspace or a code one, is refused every life tool", ctx do
    for {ws, name} <- [{ctx.home, "hronir"}, {ctx.code, "revel"}] do
      token = token_for(ws, name)
      session = handshake(token)

      for {{tool, args}, i} <- Enum.with_index(tools(ctx), 10) do
        result = call(token, session, i, tool, args)
        assert result["isError"], "#{name} ran #{tool}"
        assert hd(result["content"])["text"] =~ "not_yours", "#{name} #{tool}"
      end
    end

    assert Enum.map(Server.Life.status(ctx.home.id).quests, & &1.title) == ["book the dentist"]
  end

  test "the assistant seat on the home workspace runs every life tool", ctx do
    token = token_for(ctx.home, "ada")
    session = handshake(token)

    for {{tool, args}, i} <- Enum.with_index(tools(ctx), 10) do
      # routine_done may say not_due: a fresh daily routine is not due yet, but it is ada's to ask
      result = call(token, session, i, tool, args)
      refute hd(result["content"])["text"] =~ "not_yours", "ada refused #{tool}"
    end
  end

  test "the operator's own session runs a life tool, anywhere", ctx do
    {:ok, _} = Staff.register_agent(%{name: "andrew", mandate: "the human", engine: "claude-code"})
    token = token_for(ctx.code, "andrew")
    session = handshake(token)

    refute call(token, session, 10, "life_status", %{workspace_id: ctx.home.id})["isError"]
  end

  defp handshake(token) do
    {200, headers, _} = post(token, nil, initialize_request())
    session = header(headers, "mcp-session-id")
    post(token, session, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    session
  end

  defp call(token, session, id, tool, arguments) do
    {200, _, %{"result" => result}} =
      post(token, session, request(id, "tools/call", %{"name" => tool, "arguments" => arguments}))

    result
  end

  defp initialize_request do
    request(1, "initialize", %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "life-test", "version" => "0.0.0"}
    })
  end

  defp request(id, method, params), do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp post(token, session, body) do
    headers =
      [
        {~c"accept", ~c"application/json, text/event-stream"},
        {~c"authorization", String.to_charlist("Bearer " <> token)}
      ] ++ if(session, do: [{~c"mcp-session-id", String.to_charlist(session)}], else: [])

    {:ok, {{_http, status, _reason}, resp_headers, resp_body}} =
      :httpc.request(
        :post,
        {Process.get(:mcp_url), headers, ~c"application/json", JSON.encode!(body)},
        [],
        body_format: :binary
      )

    {status, resp_headers, decode_body(resp_headers, resp_body)}
  end

  defp decode_body(headers, body) do
    content_type = to_string(header(headers, "content-type") || "")

    cond do
      body in [nil, "", []] -> nil
      String.contains?(content_type, "event-stream") -> body |> String.split("\n") |> Enum.find_value(&sse_data/1)
      true -> JSON.decode!(body)
    end
  end

  defp sse_data(line) do
    case String.trim_leading(line, "data: ") do
      ^line -> nil
      data -> JSON.decode!(data)
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(to_string(k)) == name, do: to_string(v) end)
  end
end
