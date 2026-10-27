defmodule Server.MCP.AuthorshipTest do
  # #679, the #8669 shape: one seat (nolan) with two live sessions on two threads. Each tool call's
  # row carries the SESSION of the connection that made it, read from the token's claims (what
  # `Server.MCP.TokenValidator` hands the frame), so a later "that wasn't me" is checked against
  # the row, never against a name. A system author, with no connection, stays NULL.
  use ExUnit.Case, async: false

  alias Anubis.Server.Context
  alias Anubis.Server.Frame
  alias Server.Channel
  alias Server.MCP.Tokens
  alias Server.MCP.TokenValidator
  alias Server.MCP.Tool
  alias Server.Repo
  alias Server.Staff
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Work", roster: [%{"archetype" => "qa", "name" => "nolan"}]})
    {:ok, a} = Channel.open_thread(%{title: "thread A", workspace_id: ws.id})
    {:ok, b} = Channel.open_thread(%{title: "thread B", workspace_id: ws.id})
    nolan = Staff.agent_by_name("nolan")
    {:ok, sa} = Staff.start_session(%{agent_id: nolan.id, thread_id: a.id, pane_ref: "%9"})
    {:ok, sb} = Staff.start_session(%{agent_id: nolan.id, thread_id: b.id, pane_ref: "%12"})
    %{a: a, b: b, nolan: nolan, sa: sa, sb: sb}
  end

  # The frame a connection on `thread` as `agent` carries: the validator's own claims for a token
  # minted for the pair, so the session is the live one it resolves, never a value this test picks.
  defp frame(thread, agent) do
    {:ok, claims} = TokenValidator.validate_token(Tokens.mint(thread, agent), %{resource: "tlon"})
    %Frame{context: %Context{auth: %{raw_claims: claims}}}
  end

  defp written(frame) do
    {:reply, post, _} = Tool.PostMessage.execute(%{body: "hello"}, frame)
    {:reply, check, _} = Tool.RecordCheck.execute(%{cmd: "true", exit: 0, tail: ""}, frame)
    {:reply, ticket, _} = Tool.FileTicket.execute(%{title: "t #{System.unique_integer()}"}, frame)
    refute post.isError or check.isError or ticket.isError

    %{
      message: Repo.get!(Server.Message, json(post)["message_id"]),
      event: Repo.get!(Server.Event, json(check)["event_id"]),
      ticket: Repo.get!(Server.Ticket, json(ticket)["id"])
    }
  end

  defp json(%{content: content}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    JSON.decode!(text)
  end

  test "each session's post, check and ticket carry its own session id", ctx do
    assert ctx.sa.id != ctx.sb.id
    from_a = written(frame(ctx.a, ctx.nolan))
    from_b = written(frame(ctx.b, ctx.nolan))

    for row <- Map.values(from_a), do: assert(row.session_id == ctx.sa.id)
    for row <- Map.values(from_b), do: assert(row.session_id == ctx.sb.id)
    assert from_a.message.author == "nolan" and from_b.message.author == "nolan"
  end

  test "a system author's post keeps NULL", ctx do
    {:ok, m} = Channel.post(%{thread_id: ctx.a.id, author: "tlon", body: "stage brief"})
    assert Repo.reload!(m).session_id == nil
  end
end
