defmodule Server.MCP.ServerTest do
  # The sovereign channel, proven END TO END over the wire (pi doc §2a/§4): a raw
  # JSON-RPC client — deliberately NOT the anubis client, which would only prove
  # anubis agrees with itself ("a test that reads our own files proves only that
  # we were consistent", §8) — initializes, registers, and drives every slice-1
  # tool; every assertion reads back through SQLite. Bandit serves loopback-only.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Fact
  alias Server.Issue
  alias Server.MCP
  alias Server.Message
  alias Server.Presence
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Thread

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: {:streamable_http, start: true}})

    # port 0: the OS picks a free one, so parallel suites (a coworker's check, the merge queue's
    # gate) never fight over a fixed port
    bandit = start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    Process.put(:mcp_url, ~c"http://127.0.0.1:#{port}/mcp")

    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
    {:ok, agent} = Staff.register_agent(%{name: "Carl", mandate: "review", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)

    %{thread: thread, agent: agent, token: token}
  end

  test "a request with no bearer token is refused with 401", %{} do
    {status, _headers, _body} = post(nil, nil, initialize_request())
    assert status == 401
  end

  test "a token this node never minted is refused with 401" do
    {status, _headers, _body} = post("counterfeit", nil, initialize_request())
    assert status == 401
  end

  test "the full slice-1 loop: initialize, register, post, bank, raise, done, read back",
       %{thread: thread, agent: agent, token: token} do
    # -- initialize: the MCP handshake; the session id comes back in a header.
    {200, headers, %{"result" => init}} = post(token, nil, initialize_request())
    assert init["serverInfo"]["name"] == "tlon"
    session = header(headers, "mcp-session-id")
    assert is_binary(session)

    {status, _, _} = post(token, session, notification("notifications/initialized"))
    assert status in [200, 202]

    # -- tools/list: the slice-1 surface, visible to any MCP client.
    {200, _, %{"result" => %{"tools" => tools}}} = post(token, session, request(2, "tools/list"))
    names = tools |> Enum.map(& &1["name"]) |> Enum.sort()

    assert names ==
             Enum.sort([
               "register",
               "post_message",
               "advance_stage",
               "submit_review",
               "send_back",
               "bank_fact",
               "raise_issue",
               "record_done",
               "add_todo",
               "complete_todo",
               "raise_question",
               "resolve_question",
               "ask_operator",
               "finish",
               "record_check",
               "recheck_fact",
               "open_thread",
               "close_thread",
               "staff_child",
               "assign_lead",
               "switch_thread",
               "consult_peer",
               "spawn_crew",
               "kill_crew",
               "presence_thinking",
               "presence_doing",
               "presence_idle",
               "take_wakes",
               "put_back_wakes",
               "office_glance",
               "propose_habit",
               "get_brief",
               "get_dossier",
               "get_facts",
               "get_messages",
               "search_history",
               "search_facts",
               "machine_overview",
               "consult_oracle",
               "run_playbook",
               "list_playbooks",
               "promote_playbook",
               "register_workspace",
               "list_workspaces",
               "edit_workspace",
               "remove_workspace",
               "register_project",
               "file_ticket",
               "list_tickets",
               "update_ticket",
               "start_ticket",
               "write_note",
               "get_notes",
               "push_branch",
               "operator_inbox",
               # the PM's (pm-and-release design §1)
               "release_status",
               "check_candidate",
               "propose_release",
               "set_urgency",
               # QA's (roster design §5)
               "submit_qa",
               # the librarian's
               "supersede_fact",
               "forget_fact",
               "review_proposals",
               "decide_proposal",
               "landed_facts",
               "knowledge_report",
               "life_status",
               "routine_create",
               "routine_update",
               "routine_done",
               "quest_create",
               "quest_done",
               # the source verbs (repo tools design, 2026-09-08)
               "rename_identifier",
               "outline_file",
               "edit_clause",
               "run_verb"
             ])

    # -- register: claims a session for the token's OWN (thread, agent) — no
    # thread parameter exists to misdirect.
    result = call(token, session, 3, "register", %{"pane_ref" => "w4H:pJ"})
    refute result["isError"]

    db_session = Staff.session_for_thread(thread)
    assert db_session.agent_id == agent.id
    assert db_session.pane_ref == "w4H:pJ"

    # -- post_message: author is the bound agent, never a parameter.
    result = call(token, session, 4, "post_message", %{"body" => "starting the review"})
    refute result["isError"]

    [message] = Repo.all(Message)
    assert message.author == "Carl"
    assert message.body == "starting the review"
    assert message.thread_id == thread.id

    # -- bank_fact, derived: an agent's own finding defaults to derived — an
    # agent is never the owner — and cites its banking session.
    result =
      call(token, session, 5, "bank_fact", %{
        "kind" => "learned",
        "text" => "the flaky test is a race in drain/0",
        "check_cmd" => "mix test test/funes/switchboard_test.exs"
      })

    refute result["isError"]

    derived = Repo.one!(from(f in Fact, where: f.provenance == "derived"))
    assert derived.text == "the flaky test is a race in drain/0"
    assert derived.check_cmd == "mix test test/funes/switchboard_test.exs"
    assert derived.source_session_id == db_session.id

    # -- bank_fact, stated: reachable ONLY via the operator's own message row,
    # quoted verbatim (§4's capture path, made mechanical).
    {:ok, his} =
      Channel.post(%{thread_id: thread.id, author: "andrew", body: "tabs, not splits"})

    result =
      call(token, session, 6, "bank_fact", %{
        "kind" => "constraint",
        "from_message" => his.id
      })

    refute result["isError"]

    stated = Repo.one!(from(f in Fact, where: f.provenance == "stated"))
    assert stated.text == "tabs, not splits"

    # -- and NOT via an agent's message: quoting Carl is not the owner's word.
    result =
      call(token, session, 7, "bank_fact", %{
        "kind" => "constraint",
        "from_message" => message.id
      })

    assert result["isError"]

    # -- nor from a message on ANOTHER thread: the connection's thread is the law.
    {:ok, elsewhere} = Channel.open_thread(%{title: "other"})

    {:ok, foreign} =
      Channel.post(%{thread_id: elsewhere.id, author: "andrew", body: "unrelated"})

    result =
      call(token, session, 8, "bank_fact", %{
        "kind" => "constraint",
        "from_message" => foreign.id
      })

    assert result["isError"]

    # -- raise_issue: the STACK's tracker; found_by is the bound agent.
    result =
      call(token, session, 9, "raise_issue", %{
        "summary" => "termbox NIF crashes on resize",
        "evidence" => "aleph pane, 2026-08-15 session"
      })

    refute result["isError"]

    [issue] = Repo.all(Issue)
    assert issue.found_by == "Carl"
    assert issue.thread_id == thread.id

    # -- record_done: a done claim carries its evidence ("a claim that something
    # works is backed by having run it").
    result =
      call(token, session, 10, "record_done", %{
        "text" => "review shipped",
        "evidence" => "mise run check → 99 tests, 0 failures"
      })

    refute result["isError"]

    # -- get_dossier: the brief reads back everything above, with counts and the
    # read-time certainty rank on every fact (§4a: the certainty axis is a query).
    result = call(token, session, 11, "get_dossier", %{})
    refute result["isError"]
    brief = decode_tool_json(result)

    assert brief["goal"] == "review PR 329"
    assert brief["learnings"]["more"] == 0
    texts = Enum.map(brief["learnings"]["shown"], & &1["text"])
    assert "tabs, not splits" in texts

    certainties =
      Map.new(brief["learnings"]["shown"], fn f -> {f["text"], f["certainty"]} end)

    assert certainties["tabs, not splits"] == "stated"
    assert certainties["the flaky test is a race in drain/0"] == "checked"

    assert Enum.any?(brief["blockers"]["shown"], &(&1["summary"] =~ "termbox"))
    # DONE is the merged view — the record_done outcome rides in as a source:"event" entry.
    assert Enum.any?(brief["done"]["shown"], &(&1["source"] == "event" and &1["summary"] == "review shipped"))
    assert Enum.any?(brief["recent"], &(&1["body"] == "starting the review"))
  end

  test "an unchecked derived fact reads back as an opinion — the §4a query", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    call(token, session, 4, "bank_fact", %{
      "kind" => "learned",
      "text" => "the footer flicker is probably the double repaint"
    })

    brief = decode_tool_json(call(token, session, 5, "get_dossier", %{}))
    [fact] = brief["learnings"]["shown"]
    assert fact["certainty"] == "opinion"
    assert fact["check_cmd"] == nil
  end

  test "bank_fact stores intent (what the fact was for)", %{thread: thread, token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    result =
      call(token, session, 4, "bank_fact", %{
        "kind" => "learned",
        "text" => "x",
        "intent" => "for the value loop"
      })

    refute result["isError"]

    fact = Repo.get_by!(Fact, thread_id: thread.id, text: "x")
    assert fact.intent == "for the value loop"
  end

  test "add_todo / complete_todo — the activity axis over the wire", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    r1 = call(token, session, 4, "add_todo", %{"text" => "wire the composer"})
    refute r1["isError"]
    call(token, session, 5, "add_todo", %{"text" => "then the footer"})
    first_id = decode_tool_json(r1)["todo_id"]

    # open todos in insertion order; NEXT is the first open
    brief = decode_tool_json(call(token, session, 6, "get_dossier", %{}))
    assert Enum.map(brief["todos"]["shown"], & &1["text"]) == ["wire the composer", "then the footer"]
    assert brief["next"]["text"] == "wire the composer"

    refute call(token, session, 7, "complete_todo", %{"id" => first_id})["isError"]

    # NEXT advances; the completed step rides into DONE as a source:"todo" entry
    brief2 = decode_tool_json(call(token, session, 8, "get_dossier", %{}))
    assert brief2["next"]["text"] == "then the footer"
    assert Enum.any?(brief2["done"]["shown"], &(&1["source"] == "todo" and &1["text"] == "wire the composer"))
  end

  test "open_thread / close_thread — the deliberate cross-thread verbs", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    # open a NEW thread (not the caller's own) — returns its id
    r = call(token, session, 4, "open_thread", %{"title" => "spun-up work"})
    refute r["isError"]
    new_id = decode_tool_json(r)["thread_id"]
    assert Repo.get(Thread, new_id).state == "open"

    # close it by id — cross-thread by design
    c = call(token, session, 5, "close_thread", %{"thread_id" => new_id})
    refute c["isError"]
    assert Repo.get(Thread, new_id).state == "closed"

    # closing a missing thread is refused
    assert call(token, session, 6, "close_thread", %{"thread_id" => 999_999})["isError"]
  end

  test "close_thread on a workline that hasn't merged wants a why: superseded_by or abandoned", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})
    {:ok, line} = Server.Workline.open(%{title: "built twice", slug: "built-twice", stage: "build"})

    r = call(token, session, 3, "close_thread", %{"thread_id" => line.id, "abandoned" => "not mine to drop"})
    assert r["isError"]
    assert hd(r["content"])["text"] =~ "only its lead"
    {:ok, _} = Channel.assign_lead(line.id, "Carl")

    r = call(token, session, 4, "close_thread", %{"thread_id" => line.id})
    assert r["isError"]
    assert hd(r["content"])["text"] =~ "superseded_by"
    assert Repo.get(Thread, line.id).state == "open"

    r = call(token, session, 5, "close_thread", %{"thread_id" => line.id, "superseded_by" => "PR #234"})
    refute r["isError"]
    assert Repo.get(Thread, line.id).state == "closed"
  end

  test "consult_peer — ask a peer on another thread, the third cross-thread verb",
       %{thread: thread, token: token} do
    # A peer agent, staffed and live on its own thread.
    {:ok, peer_thread} = Channel.open_thread(%{title: "peer's work"})
    {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})
    {:ok, _} = Staff.assign(peer_thread, claude)
    {:ok, _} = Staff.start_session(%{agent_id: claude.id, thread_id: peer_thread.id, pane_ref: "wClaude"})

    session = handshake(token)
    call(token, session, 3, "register", %{})

    # The caller names a peer AGENT, never a thread id.
    r = call(token, session, 4, "consult_peer", %{"peer" => "claude", "prompt" => "is this sound?"})
    refute r["isError"]
    %{"consult_id" => consult_id, "peer_thread_id" => peer_thread_id} = decode_tool_json(r)
    assert peer_thread_id == peer_thread.id

    # The ask is a message on the PEER's thread, authored by the CALLER (the bound agent).
    [ask] = Channel.thread_messages(peer_thread)
    assert ask.author == "Carl"
    assert ask.body == "is this sound?"
    assert ask.consult_id == consult_id
    assert ask.origin_thread_id == thread.id

    # An unknown peer is refused.
    assert call(token, session, 5, "consult_peer", %{"peer" => "nobody", "prompt" => "hi"})["isError"]
  end

  test "record_check — measured verification over the wire (exit keys the kind)", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    pass = call(token, session, 4, "record_check", %{"cmd" => "mise run check", "exit" => 0, "tail" => "0 failures"})
    refute pass["isError"]
    assert decode_tool_json(pass)["kind"] == "check_passed"

    fail = call(token, session, 5, "record_check", %{"cmd" => "mix test", "exit" => 1, "tail" => "1 failure"})
    assert decode_tool_json(fail)["kind"] == "check_failed"

    # get_dossier: CHECKS surfaces both, newest first
    brief = decode_tool_json(call(token, session, 6, "get_dossier", %{}))
    assert Enum.any?(brief["checks"]["shown"], &(&1["cmd"] == "mix test" and &1["passed"] == false))
    assert Enum.any?(brief["checks"]["shown"], &(&1["cmd"] == "mise run check" and &1["passed"] == true))
  end

  test "recheck_fact — re-verify a fact's OWN check_cmd over the wire (drift signal)",
       %{thread: thread, token: token} do
    {:ok, fact} =
      Dossier.bank_fact(%{
        thread_id: thread.id,
        kind: "learned",
        text: "the drain re-delivers on restart",
        provenance: "derived",
        check_cmd: "mix test test/funes/switchboard_test.exs"
      })

    session = handshake(token)
    call(token, session, 3, "register", %{})

    ok = call(token, session, 4, "recheck_fact", %{"id" => fact.id, "exit" => 0, "tail" => "3 tests, 0 failures"})
    refute ok["isError"]
    assert decode_tool_json(ok)["kind"] == "check_passed"

    # the re-verification surfaces in CHECKS, pinned to the fact's OWN check_cmd
    brief = decode_tool_json(call(token, session, 5, "get_dossier", %{}))
    assert Enum.any?(brief["checks"]["shown"], &(&1["cmd"] == fact.check_cmd and &1["passed"] == true))
  end

  test "recheck_fact refuses a fact on another thread — identity scoping", %{token: token} do
    {:ok, other} = Channel.open_thread(%{title: "elsewhere"})

    {:ok, foreign} =
      Dossier.bank_fact(%{
        thread_id: other.id,
        kind: "learned",
        text: "not yours",
        provenance: "derived",
        check_cmd: "true"
      })

    session = handshake(token)
    call(token, session, 3, "register", %{})
    result = call(token, session, 4, "recheck_fact", %{"id" => foreign.id, "exit" => 0})

    assert result["isError"]
  end

  test "recheck_fact refuses a fact with no check_cmd — nothing to re-run", %{thread: thread, token: token} do
    {:ok, opinion} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "an unverifiable hunch", provenance: "derived"})

    session = handshake(token)
    call(token, session, 3, "register", %{})
    result = call(token, session, 4, "recheck_fact", %{"id" => opinion.id, "exit" => 0})

    assert result["isError"]
  end

  test "raise_question / resolve_question — UNKNOWNS over the wire", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    r = call(token, session, 4, "raise_question", %{"text" => "does raxol support embedding?"})
    refute r["isError"]
    qid = decode_tool_json(r)["question_id"]

    # get_dossier: the open question surfaces as an UNKNOWN
    brief = decode_tool_json(call(token, session, 5, "get_dossier", %{}))
    assert Enum.any?(brief["unknowns"]["shown"], &(&1["text"] == "does raxol support embedding?"))

    refute call(token, session, 6, "resolve_question", %{"id" => qid, "resolution" => "yes, via ghostty_ex"})[
             "isError"
           ]

    # resolved: it leaves UNKNOWNS
    brief2 = decode_tool_json(call(token, session, 7, "get_dossier", %{}))
    refute Enum.any?(brief2["unknowns"]["shown"], &(&1["text"] == "does raxol support embedding?"))
  end

  test "ask_operator posts the question and parks this thread on the operator", %{token: token, thread: thread} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    refute call(token, session, 4, "ask_operator", %{"question" => "A or B?"})["isError"]

    assert %Server.Thread{awaiting: "andrew"} = Server.Repo.get(Server.Thread, thread.id)
    assert %{body: "A or B?"} = List.last(Channel.thread_messages(thread))
  end

  test "ask_operator with `about` names the thread the decision is about, so its close withdraws it",
       %{token: token, thread: thread} do
    {:ok, about} = Channel.open_thread(%{title: "toy step 1"})
    session = handshake(token)
    call(token, session, 3, "register", %{})

    refute call(token, session, 4, "ask_operator", %{
             "question" => "how should it move?",
             "options" => ["allow", "advance"],
             "about" => about.id
           })["isError"]

    assert [%{thread_id: thread_id, payload: %{"about" => about_id}}] = Server.Attention.open_asks()
    assert {thread_id, about_id} == {thread.id, about.id}
  end

  test "resolve_question refuses a question on another thread — identity scoping", %{token: token} do
    {:ok, other} = Channel.open_thread(%{title: "elsewhere"})
    {:ok, foreign} = Dossier.raise_question(%{thread_id: other.id, text: "not yours"})

    session = handshake(token)
    call(token, session, 3, "register", %{})
    result = call(token, session, 4, "resolve_question", %{"id" => foreign.id})

    assert result["isError"]
    assert Repo.get(Server.Question, foreign.id).state == "open"
  end

  test "complete_todo refuses a todo on another thread — identity scoping", %{token: token} do
    {:ok, other} = Channel.open_thread(%{title: "elsewhere"})
    {:ok, foreign} = Dossier.add_todo(%{thread_id: other.id, text: "not yours"})

    session = handshake(token)
    call(token, session, 3, "register", %{})
    result = call(token, session, 4, "complete_todo", %{"id" => foreign.id})

    assert result["isError"]
    # and it stays open — a cross-thread complete is a no-op on the row
    assert is_nil(Repo.get(Server.Todo, foreign.id).done_at)
  end

  test "every authenticated call is measured activity — warmth bumps without a heartbeat",
       %{thread: thread, token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    # Backdate the session cold (an hour past the warmth window), then make ONE
    # ordinary tool call: the call arriving at funes IS the activity.
    db_session = Staff.session_for_thread(thread)
    cold = DateTime.utc_now() |> DateTime.shift(hour: -2) |> DateTime.truncate(:second)

    Repo.update_all(from(s in Session, where: s.id == ^db_session.id),
      set: [last_active_at: cold]
    )

    call(token, session, 4, "get_dossier", %{})

    reloaded = Repo.get!(Session, db_session.id)
    assert Presence.warm?(reloaded.last_active_at)
  end

  test "take_wakes hands the session the wakes queued for it, once, oldest first", %{
    thread: thread,
    agent: agent,
    token: token
  } do
    session = handshake(token)
    {:ok, _} = Server.Wake.queue(thread.id, agent.name, "first")
    {:ok, _} = Server.Wake.queue(thread.id, agent.name, "second")
    {:ok, _} = Server.Wake.queue(thread.id, "someone-else", "not yours")

    assert decode_tool_json(call(token, session, 3, "take_wakes", %{})) == ["first", "second"]
    assert decode_tool_json(call(token, session, 4, "take_wakes", %{})) == []
  end

  test "put_back_wakes queues a taken wake again for the same seat, so the next take hands it over",
       %{thread: thread, agent: agent, token: token} do
    session = handshake(token)
    {:ok, _} = Server.Wake.queue(thread.id, agent.name, "lost")
    ["lost"] = decode_tool_json(call(token, session, 3, "take_wakes", %{}))

    assert decode_tool_json(call(token, session, 4, "put_back_wakes", %{"prompts" => ["lost"]})) == %{"put_back" => 1}
    assert Server.Wake.take(thread.id, "someone-else") == []
    assert decode_tool_json(call(token, session, 5, "take_wakes", %{})) == ["lost"]
  end

  test "office_glance: who else is on, what is red on my thread, my own voice — and reading it is not activity",
       %{thread: thread, agent: agent, token: token} do
    {:ok, ws} = Server.Workspaces.register(%{name: "Glanced"})
    Repo.update_all(from(t in Thread, where: t.id == ^thread.id), set: [workspace_id: ws.id])
    {:ok, peer} = Staff.register_agent(%{name: "lonnrot", mandate: "review", engine: "claude"})
    {:ok, peer_thread} = Channel.open_thread(%{title: "case notes", workspace_id: ws.id})
    {:ok, _} = Staff.start_session(%{thread_id: peer_thread.id, agent_id: peer.id, pane_ref: "%1"})
    {:ok, _} = Server.Dossier.raise_issue(%{thread_id: thread.id, summary: "the band overflows", raised_by: agent.name})

    session = handshake(token)
    call(token, session, 3, "register", %{})
    db_session = Staff.session_for_thread(thread)
    cold = DateTime.utc_now() |> DateTime.shift(hour: -2) |> DateTime.truncate(:second)
    Repo.update_all(from(s in Session, where: s.id == ^db_session.id), set: [last_active_at: cold])

    glance = decode_tool_json(call(token, session, 4, "office_glance", %{}))

    assert %{"agent" => "lonnrot", "thread_id" => peer_id} = Enum.find(glance["crew"], &(&1["agent"] == "lonnrot"))
    assert peer_id == peer_thread.id
    assert [%{"text" => "the band overflows"}] = glance["red"]
    assert Map.has_key?(glance, "persona") and Map.has_key?(glance, "landed")
    assert Repo.get!(Session, db_session.id).last_active_at == cold
  end

  test "a seat's cut tools are refused by the server too, not only hidden from its model — but it may still register",
       %{token: _token} do
    {:ok, ws} = Server.Workspaces.register(%{name: "Fenced"})
    {:ok, seat} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
    {:ok, thread} = Channel.open_thread(%{title: "build it", workspace_id: ws.id})
    agent = Repo.get!(Server.Agent, seat.agent_id)
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    refute call(token, session, 3, "register", %{})["isError"]
    r = call(token, session, 4, "propose_release", %{})
    assert r["isError"]
    assert hd(r["content"])["text"] =~ "hronir's seat does not have propose_release"
    refute call(token, session, 5, "get_dossier", %{})["isError"]
  end

  test "taking wakes is not activity — a session idle past its window stays cold, so its wake reads unheard",
       %{thread: thread, token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})
    db_session = Staff.session_for_thread(thread)
    cold = DateTime.utc_now() |> DateTime.shift(hour: -2) |> DateTime.truncate(:second)
    Repo.update_all(from(s in Session, where: s.id == ^db_session.id), set: [last_active_at: cold])

    call(token, session, 4, "take_wakes", %{})

    assert Repo.get!(Session, db_session.id).last_active_at == cold
  end

  test "get_facts returns the full corpus past the brief's cap", %{thread: thread, token: token} do
    session = handshake(token)

    for n <- 1..7 do
      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "fact #{n}",
          provenance: "derived"
        })
    end

    facts = decode_tool_json(call(token, session, 3, "get_facts", %{}))
    assert length(facts) == 7
  end

  test "a get_facts read cites each returned fact once a day, and a cited fact outranks an uncited peer",
       %{thread: thread, token: token} do
    session = handshake(token)
    fact_ids = for n <- 1..2, do: bank!(thread, "fact #{n}").id

    call(token, session, 3, "get_facts", %{})
    call(token, session, 4, "get_facts", %{})

    assert Enum.sort(cited_fact_ids(thread)) == Enum.sort(fact_ids)

    peer = bank!(thread, "an uncited peer")
    set = Server.Recall.working_set_for_thread(thread, include_pinned: false)
    strength = Map.new(set, &{&1.id, &1.strength})
    assert strength[hd(fact_ids)] > strength[peer.id]
  end

  test "search_facts cites only the facts that matched its query", %{thread: thread, token: token} do
    session = handshake(token)
    hit = bank!(thread, "the gate runs unsandboxed")
    _miss = bank!(thread, "postgres is the truth")

    call(token, session, 3, "search_facts", %{"query" => "unsandboxed"})

    assert cited_fact_ids(thread) == [hit.id]
  end

  test "the brief and the always-loaded constraints are readable as MCP resources",
       %{thread: thread, token: token} do
    # The free half of anubis: the same single reads (Board.brief,
    # Dossier.always_loaded_constraints) exposed on the resources primitive — a
    # second protocol DOOR, never a second source. The extension reads the
    # resource to brief; the model calls the tool to refresh.
    session = handshake(token)

    {:ok, _} =
      Dossier.bank_fact(%{
        thread_id: thread.id,
        kind: "learned",
        text: "a thread learning",
        provenance: "derived"
      })

    {:ok, _} =
      Dossier.bank_fact(%{
        kind: "constraint",
        text: "in production, Andrew presses Enter",
        provenance: "stated"
      })

    {200, _, %{"result" => %{"resources" => resources}}} =
      post(token, session, request(3, "resources/list"))

    uris = resources |> Enum.map(& &1["uri"]) |> Enum.sort()
    assert uris == ["tlon://brief", "tlon://constraints", "tlon://habits"]

    {200, _, %{"result" => %{"contents" => [dossier]}}} =
      post(token, session, request(4, "resources/read", %{"uri" => "tlon://brief"}))

    brief = JSON.decode!(dossier["text"])
    assert brief["goal"] == "review PR 329"
    assert Enum.any?(brief["learnings"]["shown"], &(&1["text"] == "a thread learning"))

    {200, _, %{"result" => %{"contents" => [constraints]}}} =
      post(token, session, request(5, "resources/read", %{"uri" => "tlon://constraints"}))

    loaded = JSON.decode!(constraints["text"])
    assert Enum.any?(loaded, &(&1["text"] == "in production, Andrew presses Enter"))
    assert Enum.all?(loaded, &(&1["certainty"] == "stated"))
  end

  test "spawn_crew / kill_crew staff a role onto the connection's OWN thread via the crew backend",
       %{token: token, thread: thread} do
    Application.put_env(:server, :crew, Server.Crew.Test)
    Application.put_env(:server, :test_pid, self())
    on_exit(fn -> Application.delete_env(:server, :crew) end)

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r = call(token, session, 4, "spawn_crew", %{"task" => "review the diff"})
    refute r["isError"]
    payload = decode_tool_json(r)
    # no thread parameter — the reviewer joins THIS connection's thread; role defaults to reviewer
    assert payload["thread_id"] == thread.id
    assert payload["role"] == "reviewer"
    assert_received {:crew_spawn, "reviewer", thread_id, "review the diff"}
    assert thread_id == thread.id

    refute call(token, session, 5, "kill_crew", %{})["isError"]
    assert_received {:crew_kill, "reviewer", ^thread_id}
  end

  test "staff_child opens a worker-led CHILD thread parented at the caller (lead-as-manager, Slice 4D)",
       %{token: token, thread: thread} do
    {:ok, _} = Staff.register_agent(%{name: "hronir-machine", mandate: "build", engine: "fresh"})

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "typing presence slices",
        "lead" => "hronir-machine",
        "brief" => "Execute docs/plans/2026-08-22 plan, slice by slice."
      })

    refute r["isError"]
    payload = decode_tool_json(r)
    tid = payload["thread_id"]
    assert payload["lead"] == "hronir-machine"

    # The staffed thread is exactly what the staffing pass's leaf sweep spawns from: a worker lead...
    assert Channel.thread_lead(tid) == "hronir-machine"

    # ...parented at the CALLER's thread, so its close reports up to the manager (Slice 4D)...
    assert Repo.get!(Thread, tid).parent_thread_id == thread.id

    # ...and the brief on the thread (authored by the CALLER — identity from the token, no spoof).
    [first] = Repo.all(from m in Message, where: m.thread_id == ^tid, order_by: m.id)
    assert first.author == "Carl"
    assert first.body =~ "slice by slice"
  end

  test "staff_child refuses a ticket already worked, and opens nothing", %{token: token} do
    {:ok, _} = Staff.register_agent(%{name: "hronir-dup", mandate: "build", engine: "fresh"})
    {:ok, ws} = Server.Workspaces.register(%{name: "Claims"})
    {:ok, t} = Server.Tickets.file(%{workspace_id: ws.id, title: "built by hand"})
    {:ok, _} = Server.Tickets.claim(t, "uqbar")
    before = Repo.aggregate(Thread, :count)

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "built by hand",
        "lead" => "hronir-dup",
        "brief" => "Build it.",
        "ticket_id" => t.id
      })

    assert r["isError"]
    assert hd(r["content"])["text"] =~ "claimed by uqbar"
    assert Repo.aggregate(Thread, :count) == before
  end

  test "staff_child with no lead takes the server's pick by grade: the greybeard for greybeard work" do
    {:ok, ws} = Server.Workspaces.register(%{name: "Picking"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder", grade: "junior"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder", grade: "greybeard"})
    {:ok, manager} = Staff.register_agent(%{name: "tertius", mandate: "route", engine: "fresh"})
    {:ok, home} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id, agent_id: manager.id})
    token = MCP.Tokens.mint(home, manager)
    session = handshake(token)
    call(token, session, 3, "register", %{})

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "add a column",
        "brief" => "Write the migration.",
        "grade" => "greybeard"
      })

    refute r["isError"]
    assert decode_tool_json(r)["lead"] == "hronir"

    r =
      call(token, session, 5, "staff_child", %{
        "title" => "tweak a label",
        "brief" => "Rename the lamp's tooltip.",
        "grade" => "junior"
      })

    assert decode_tool_json(r)["lead"] == "daneri"
  end

  describe "send_back and follow-ups" do
    setup do
      roster = [
        %{"archetype" => "builder", "name" => "hronir"},
        %{"archetype" => "planner", "name" => "yu"},
        %{"archetype" => "reviewer", "name" => "lonnrot"},
        %{"archetype" => "qa", "name" => "nolan"}
      ]

      {:ok, ws} = Server.Workspaces.register(%{name: "Backwards", roster: roster})
      {:ok, lobby} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})

      {:ok, wl} =
        Server.Workline.open(%{title: "bench: shape", slug: "shape", stage: "review", workspace_id: ws.id})

      %{lobby: lobby, wl: wl}
    end

    defp as(name, thread) do
      token = MCP.Tokens.mint(thread, Staff.agent_by_name(name))
      session = handshake(token)
      call(token, session, 3, "register", %{})
      {token, session}
    end

    test "the tech lead sends a workline back to plan from the lobby; a reviewer is told to ask him",
         %{lobby: lobby, wl: wl} do
      {token, session} = as("lonnrot", lobby)
      ask = %{"stage" => "plan", "why" => "the fixtures share one db", "thread_id" => wl.id}
      r = call(token, session, 4, "send_back", ask)
      assert r["isError"]
      assert get_in(r, ["content", Access.at(0), "text"]) =~ "hronir"
      assert Repo.get!(Thread, wl.id).stage == "review"

      {token, session} = as("hronir", lobby)
      refute call(token, session, 4, "send_back", ask)["isError"]
      assert Repo.get!(Thread, wl.id).stage == "plan"
    end

    test "submit_qa files its follow-ups as held tickets on the workline", %{wl: wl} do
      {token, session} = as("nolan", wl)

      r =
        call(token, session, 4, "submit_qa", %{
          "verdict" => "fail",
          "report" => "R doesn't reload",
          "follow_ups" => ["the help line wraps at 80 cols"]
        })

      refute r["isError"]
      assert decode_tool_json(r)["follow_ups"] == 1
      assert [t] = Repo.all(from t in Server.Ticket, where: t.title == "the help line wraps at 80 cols")
      assert "held" in t.labels
    end

    test "a refused submit_qa files no follow-ups", %{wl: wl} do
      {token, session} = as("nolan", wl)
      ask = %{"verdict" => "maybe", "report" => "r", "follow_ups" => ["never filed"]}
      assert call(token, session, 4, "submit_qa", ask)["isError"]
      assert Repo.all(from t in Server.Ticket, where: t.title == "never filed") == []
    end
  end

  test "only the manager staffs from the lobby — a lead there is refused, opening nothing" do
    {:ok, ws} = Server.Workspaces.register(%{name: "Routing"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "tertius", archetype: "surveyor"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "ireneo", archetype: "builder"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "yu", archetype: "builder"})
    {:ok, lobby} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})
    ask = %{"title" => "build the plan", "lead" => "ireneo", "brief" => "Build T1→T6."}

    yu = Staff.agent_by_name("yu")
    token = MCP.Tokens.mint(lobby, yu)
    session = handshake(token)
    call(token, session, 3, "register", %{})
    before = Repo.aggregate(Thread, :count)

    r = call(token, session, 4, "staff_child", ask)
    assert r["isError"]
    assert get_in(r, ["content", Access.at(0), "text"]) =~ "seat does not have staff_child"
    assert Repo.aggregate(Thread, :count) == before

    tertius = Staff.agent_by_name("tertius")
    token = MCP.Tokens.mint(lobby, tertius)
    session = handshake(token)
    call(token, session, 3, "register", %{})
    refute call(token, session, 4, "staff_child", ask)["isError"]
  end

  test "staff_child and spawn_crew refuse a blank brief, opening nothing", %{token: token} do
    {:ok, _} = Staff.register_agent(%{name: "hronir-machine", mandate: "build", engine: "fresh"})
    Application.put_env(:server, :crew, Server.Crew.Test)
    Application.put_env(:server, :test_pid, self())
    on_exit(fn -> Application.delete_env(:server, :crew) end)

    session = handshake(token)
    call(token, session, 3, "register", %{})
    before = Repo.aggregate(Thread, :count)

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "scratch check",
        "lead" => "hronir-machine",
        "brief" => "  \n"
      })

    assert r["isError"]
    assert Repo.aggregate(Thread, :count) == before

    assert call(token, session, 5, "spawn_crew", %{"task" => ""})["isError"]
    refute_received {:crew_spawn, _, _, _}
  end

  test "assign_lead (re)staffs an existing thread by id — tertius's orchestrator verb (Slice 4D)",
       %{token: token} do
    {:ok, _} = Staff.register_agent(%{name: "menard-machine", mandate: "review", engine: "fresh"})
    {:ok, target} = Channel.open_thread(%{title: "the diff to review", scope: "machine"})

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r = call(token, session, 4, "assign_lead", %{"thread_id" => target.id, "lead" => "menard-machine"})
    refute r["isError"]
    assert Channel.thread_lead(target.id) == "menard-machine"

    # A missing thread and an unregistered lead each refuse cleanly.
    assert call(token, session, 5, "assign_lead", %{"thread_id" => 999_999, "lead" => "menard-machine"})["isError"]
    assert call(token, session, 6, "assign_lead", %{"thread_id" => target.id, "lead" => "ghost-machine"})["isError"]
  end

  test "finish posts the summary and closes the caller's own thread", %{token: token, thread: thread} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    refute call(token, session, 4, "finish", %{"summary" => "inbox A shipped, tests green"})["isError"]

    assert %Thread{state: "closed"} = Repo.get(Thread, thread.id)
    assert %{body: "inbox A shipped, tests green"} = List.last(Channel.thread_messages(thread))
  end

  test "the workspace's standing thread is never closed by an agent: finish posts but leaves it open, close_thread refuses" do
    {:ok, ws} = Server.Workspaces.register(%{name: "Standing"})
    {:ok, lobby} = Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "Daneri", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(lobby, agent)
    session = handshake(token)
    call(token, session, 2, "register", %{})

    r = call(token, session, 3, "finish", %{"summary" => "ticket #15 done"})
    refute r["isError"]
    assert decode_tool_json(r)["stays_open"] == true
    assert %Thread{state: "open"} = Repo.get(Thread, lobby.id)
    assert %{body: "ticket #15 done"} = List.last(Channel.thread_messages(lobby))

    assert call(token, session, 4, "close_thread", %{"thread_id" => lobby.id})["isError"]
    assert %Thread{state: "open"} = Repo.get(Thread, lobby.id)
  end

  test "close_thread on a plain thread holding unmerged commits tracks it and says stays_open" do
    repo = Path.join(System.tmp_dir!(), "close-tool-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)

    git = fn dir, args ->
      System.cmd("git", ["-C", dir, "-c", "user.email=t@t", "-c", "user.name=t" | args], stderr_to_stdout: true)
    end

    {_, 0} = git.(repo, ["init", "-q", "-b", "main"])
    File.write!(Path.join(repo, "README"), "seed\n")
    {_, 0} = git.(repo, ["add", "README"])
    {_, 0} = git.(repo, ["commit", "-qm", "seed"])

    {:ok, ws} = Server.Workspaces.register(%{name: "Strand"})

    {:ok, project} =
      Server.Projects.register(%{workspace_id: ws.id, name: "p", repos: [%{"name" => "r", "path" => repo}]})

    {:ok, plain} = Channel.open_thread(%{title: "plain", workspace_id: ws.id, project_id: project.id})
    {:ok, wt} = Server.Worktree.ensure(repo, "t#{plain.id}")
    File.write!(Path.join(wt, "w.txt"), "x\n")
    {_, 0} = git.(wt, ["add", "w.txt"])
    {_, 0} = git.(wt, ["commit", "-qm", "work"])

    {:ok, caller} = Channel.open_thread(%{title: "caller", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "closer", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(caller, agent)
    session = handshake(token)
    call(token, session, 2, "register", %{})

    r = call(token, session, 3, "close_thread", %{"thread_id" => plain.id})
    refute r["isError"]
    assert decode_tool_json(r)["stays_open"] == true
    assert %Thread{state: "open", stage: "build"} = Repo.get(Thread, plain.id)
  end

  test "finish on a workline that hasn't merged posts the summary and leaves it open — the merge queue closes it" do
    {:ok, ws} = Server.Workspaces.register(%{name: "Landing"})
    {:ok, w} = Server.Workline.open(%{title: "fanfare", slug: "fanfare-finish", stage: "review", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "nolan", mandate: "qa", engine: "fresh"})
    token = MCP.Tokens.mint(w, agent)
    session = handshake(token)

    r = call(token, session, 2, "finish", %{"summary" => "QA passed"})
    refute r["isError"]
    assert decode_tool_json(r)["stays_open"] == true
    assert %Thread{state: "open"} = Repo.get(Thread, w.id)
    assert %{body: "QA passed"} = List.last(Channel.thread_messages(w))
  end

  test "staff_child with a ticket_id moves that ticket into the thread it opens", %{token: token} do
    {:ok, _} = Staff.register_agent(%{name: "yu-machine", mandate: "plan", engine: "fresh"})
    {:ok, ws} = Server.Workspaces.register(%{name: "Ticketed"})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "inbox design"})

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "inbox design",
        "lead" => "yu-machine",
        "brief" => "Plan the cross-workspace inbox.",
        "ticket_id" => ticket.id
      })

    refute r["isError"]
    tid = decode_tool_json(r)["thread_id"]
    assert %{status: "doing"} = Server.Tickets.get(ticket.id)
    assert [{"promoted", ^tid}] = Server.Tickets.threads_of(ticket.id)
  end

  test "staff_child with workline opens the child as a workline at that stage — its lead, brief and ticket as before",
       %{token: token, thread: thread} do
    {:ok, _} = Staff.register_agent(%{name: "yu-machine", mandate: "plan", engine: "fresh"})
    {:ok, ws} = Server.Workspaces.register(%{name: "Lined"})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "finder finds tickets"})

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r =
      call(token, session, 4, "staff_child", %{
        "title" => "Finder finds tickets",
        "lead" => "yu-machine",
        "brief" => "Spec it: the finder should match open tickets by title.",
        "ticket_id" => ticket.id,
        "workline" => "spec"
      })

    refute r["isError"]
    tid = decode_tool_json(r)["thread_id"]
    child = Repo.get!(Thread, tid)
    assert {child.stage, child.parent_thread_id} == {"spec", thread.id}
    assert child.slug =~ "finder-finds-tickets"
    assert Channel.thread_lead(tid) == "yu-machine"
    assert Enum.any?(Channel.thread_messages(child), &(&1.body =~ "match open tickets by title"))
    assert [{"promoted", ^tid}] = Server.Tickets.threads_of(ticket.id)
  end

  test "staff_child refuses an unregistered lead without opening a thread", %{token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    threads_before = Repo.aggregate(Thread, :count)

    r = call(token, session, 4, "staff_child", %{"title" => "x", "lead" => "ghost-machine", "brief" => "y"})
    assert r["isError"]
    %{"text" => text} = Enum.find(r["content"], &(&1["type"] == "text"))
    assert text =~ "ghost-machine"

    assert Repo.aggregate(Thread, :count) == threads_before
  end

  test "spawn_crew reports unavailable when no crew backend is configured", %{token: token} do
    Application.delete_env(:server, :crew)

    session = handshake(token)
    call(token, session, 3, "register", %{})

    r = call(token, session, 4, "spawn_crew", %{"task" => "review the diff"})
    assert r["isError"]
    %{"text" => text} = Enum.find(r["content"], &(&1["type"] == "text"))
    assert text =~ "unavailable"
  end

  test "file_ticket with epic_id files the ticket into that epic; a non-epic parent is refused" do
    {:ok, ws} = Server.Workspaces.register(%{name: "EpicWS"})
    {:ok, thread} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "EpicFiler", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)
    {:ok, epic} = Server.Tickets.file(%{workspace_id: ws.id, title: "Toy", kind: "epic"})

    filed = token |> call(session, 2, "file_ticket", %{"title" => "step 1", "epic_id" => epic.id}) |> decode_tool_json()
    assert filed["epic_id"] == epic.id

    plain = token |> call(session, 3, "file_ticket", %{"title" => "loose"}) |> decode_tool_json()
    assert plain["epic_id"] == nil

    refused = call(token, session, 4, "file_ticket", %{"title" => "bad", "epic_id" => plain["id"]})
    assert refused["isError"]
    refute ws.id |> Server.Tickets.in_workspace() |> Enum.any?(&(&1.title == "bad"))
  end

  test "file_ticket lands in the bound thread's workspace; list_tickets reads it back" do
    {:ok, ws} = Server.Workspaces.register(%{name: "TicketWS"})
    {:ok, thread} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "Filer", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    filed =
      token
      |> call(session, 2, "file_ticket", %{"title" => "auth is fucked", "priority" => "high"})
      |> decode_tool_json()

    assert %{"id" => id, "status" => "backlog", "priority" => "high"} = filed
    assert is_integer(id)

    listed = token |> call(session, 3, "list_tickets", %{}) |> decode_tool_json()
    assert Enum.any?(listed, &(&1["id"] == id and &1["title"] == "auth is fucked"))
  end

  test "start_ticket opens a thread on the ticket and promotes it, moving the ticket to doing" do
    {:ok, ws} = Server.Workspaces.create(%{name: "StartWS"})
    {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})
    {:ok, thread} = Channel.open_thread(%{title: "work", workspace_id: ws.id, project_id: p.id})
    {:ok, agent} = Staff.register_agent(%{name: "Starter", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    filed =
      token
      |> call(session, 2, "file_ticket", %{"title" => "unbind ctrl+enter", "body" => "ghostty eats it"})
      |> decode_tool_json()

    started = token |> call(session, 3, "start_ticket", %{"id" => filed["id"]}) |> decode_tool_json()
    assert %{"thread_id" => thread_id} = started
    assert is_integer(thread_id)

    started_thread = Repo.get!(Server.Thread, thread_id)
    assert started_thread.title == "unbind ctrl+enter"

    assert [%{body: body}] = for(m <- Channel.thread_messages(started_thread), m.author == "andrew", do: m)
    assert body =~ "unbind ctrl+enter"
    assert body =~ "ghostty eats it"
    assert started_thread.stage == "build"

    assert %{"status" => "doing"} = filed["id"] |> Server.Tickets.get() |> Server.MCP.Brief.ticket()
  end

  test "start_ticket refuses a missing ticket" do
    {:ok, thread} = Channel.open_thread(%{title: "starter thread"})
    {:ok, agent} = Staff.register_agent(%{name: "Starter2", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    r = call(token, session, 2, "start_ticket", %{"id" => 999_999})
    assert r["isError"]
    %{"text" => text} = Enum.find(r["content"], &(&1["type"] == "text"))
    assert text =~ "999999"
  end

  describe "operator_inbox — the manager reads what waits on the operator" do
    test "each item with the real question: the newest message no server notice wrote" do
      {:ok, ws} = Server.Workspaces.create(%{name: "InboxWS"})
      {:ok, desk} = Channel.open_thread(%{title: "manager desk", workspace_id: ws.id, scope: "machine"})
      {:ok, agent} = Staff.register_agent(%{name: "tertius", mandate: "manager", engine: "fresh"})
      token = MCP.Tokens.mint(desk, agent)

      {:ok, asked} = Channel.open_thread(%{title: "weather", workspace_id: ws.id})
      {:ok, _} = Server.Attention.ask(asked.id, "ireneo", "should I build (a) or (b)?")

      {:ok, _} =
        Channel.post(%{thread_id: asked.id, author: "tlon", body: "⟳ the server is restarting", kind: "notice"})

      items = token |> call(handshake(token), 2, "operator_inbox", %{}) |> decode_tool_json()
      assert [item] = Enum.filter(items, &(&1["thread_id"] == asked.id))
      assert item["kind"] == "question"
      assert item["asking"] =~ "ireneo: should I build (a) or (b)?"
    end
  end

  describe "the PM's tools" do
    setup do
      {:ok, ws} = Server.Workspaces.create(%{name: "PMWS"})
      {:ok, thread} = Channel.open_thread(%{title: "release desk", workspace_id: ws.id})
      {:ok, agent} = Staff.register_agent(%{name: "beatriz", mandate: "pm", engine: "fresh"})
      token = MCP.Tokens.mint(thread, agent)

      repo = Path.join(System.tmp_dir!(), "pm-tools-#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo)
      on_exit(fn -> File.rm_rf!(repo) end)

      sh = fn cmd -> {_, 0} = System.cmd("sh", ["-c", cmd], cd: repo, stderr_to_stdout: true) end

      sh.("""
      git init -q && git config user.email t@t && git config user.name t &&
      git commit -q --allow-empty -m seed && git branch live &&
      git commit -q --allow-empty -m 'office: the lamp talks' && git update-ref refs/remotes/origin/main HEAD
      """)

      Application.put_env(:server, :release_root, repo)
      on_exit(fn -> Application.delete_env(:server, :release_root) end)

      %{ws: ws, token: token, session: handshake(token)}
    end

    test "release_status: what runs, what waits on main, and main's checks", %{token: token, session: session} do
      status = token |> call(session, 2, "release_status", %{}) |> decode_tool_json()
      assert [%{"subject" => "office: the lamp talks"}] = status["waiting"]
      assert status["live"] != status["main"]
      assert Enum.any?(status["checks"], &(&1 =~ "releasable: no"))
    end

    test "propose_release is refused unless main is releasable", %{token: token, session: session} do
      r = call(token, session, 2, "propose_release", %{"changelog" => "The lamp talks."})
      assert r["isError"]
      %{"text" => text} = Enum.find(r["content"], &(&1["type"] == "text"))
      assert text =~ "not releasable"
    end

    test "set_urgency moves a ticket's priority and says what's next and why on the root thread",
         %{ws: ws, token: token, session: session} do
      {:ok, low} = Server.Tickets.file(%{workspace_id: ws.id, title: "the lamp talks", priority: "low"})
      {:ok, _} = Server.Tickets.file(%{workspace_id: ws.id, title: "the desk hums", priority: "med"})

      r =
        call(token, session, 2, "set_urgency", %{"ticket_id" => low.id, "priority" => "high", "why" => "Andrew asked"})

      refute r["isError"]
      assert Server.Tickets.get(low.id).priority == "high"

      assert [note] = for(m <- Channel.thread_messages(Channel.machine_thread(ws.id)), m.author == "beatriz", do: m)
      assert note.kind == "notice"
      assert note.body =~ "##{low.id} the lamp talks → high: Andrew asked"
      assert note.body =~ "next up: ##{low.id} the lamp talks"
    end

    test "set_urgency refuses a ticket from another workspace", %{token: token, session: session} do
      {:ok, other} = Server.Workspaces.register(%{name: "Elsewhere"})
      {:ok, t} = Server.Tickets.file(%{workspace_id: other.id, title: "theirs"})

      r = call(token, session, 2, "set_urgency", %{"ticket_id" => t.id, "priority" => "high", "why" => "x"})
      assert r["isError"]
      assert Server.Tickets.get(t.id).priority == "med"
    end
  end

  test "submit_qa: a fail sends the workline back to build with the finding; off review it is refused" do
    {:ok, thread} = Server.Workline.open(%{title: "office: R", slug: "qa-tool", stage: "review"})
    {:ok, agent} = Staff.register_agent(%{name: "nolan", mandate: "qa", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    r =
      call(token, session, 2, "submit_qa", %{"verdict" => "fail", "report" => "after R: 'R reloads' on its own server"})

    refute r["isError"]
    assert %Thread{stage: "build"} = Repo.get!(Thread, thread.id)
    assert Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "back to build" and &1.body =~ "R reloads"))

    again = call(token, session, 3, "submit_qa", %{"verdict" => "pass", "report" => "fine"})
    assert again["isError"]
  end

  test "submit_qa with thread_id: the bench's qa seat bound elsewhere files on that workline; a non-qa is refused" do
    roster = [%{"archetype" => "builder", "name" => "emma"}, %{"archetype" => "qa", "name" => "nolan"}]
    {:ok, ws} = Server.Workspaces.register(%{name: "QA off-thread", roster: roster})

    {:ok, workline} =
      Server.Workline.open(%{title: "office: R", slug: "qa-off-thread", stage: "review", workspace_id: ws.id})

    {:ok, lobby} = Channel.open_thread(%{title: "lobby"})
    args = %{"verdict" => "fail", "report" => "after R: 'R reloads'", "thread_id" => workline.id}

    emma = Staff.agent_by_name("emma")
    emma_token = MCP.Tokens.mint(lobby, emma)
    refused = call(emma_token, handshake(emma_token), 2, "submit_qa", args)
    assert refused["isError"]
    assert hd(refused["content"])["text"] =~ "seat does not have submit_qa"
    assert %Thread{stage: "review"} = Repo.get!(Thread, workline.id)

    nolan = Staff.agent_by_name("nolan")
    nolan_token = MCP.Tokens.mint(lobby, nolan)
    r = call(nolan_token, handshake(nolan_token), 2, "submit_qa", args)

    refute r["isError"]
    assert %Thread{stage: "build"} = Repo.get!(Thread, workline.id)
    assert Enum.any?(Channel.thread_messages(workline), &(&1.body =~ "R reloads"))
    assert %Thread{stage: nil} = Repo.get!(Thread, lobby.id)
  end

  test "a lead woken on the lobby acts on the workline it leads by thread_id; a non-lead is refused" do
    roster = [%{"archetype" => "builder", "name" => "emma"}, %{"archetype" => "qa", "name" => "nolan"}]
    {:ok, ws} = Server.Workspaces.register(%{name: "Lobby-bound", roster: roster})
    {:ok, workline} = Server.Workline.open(%{title: "fix", slug: "lobby-bound", stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(workline.id, "emma")
    {:ok, lobby} = Channel.open_thread(%{title: "lobby"})

    emma = Staff.agent_by_name("emma")
    token = MCP.Tokens.mint(lobby, emma)
    r = call(token, handshake(token), 2, "advance_stage", %{"thread_id" => workline.id})
    # it reached the workline: the build stage owes a commit this test never made
    assert hd(r["content"])["text"] =~ "owed artifact"

    nolan = Staff.agent_by_name("nolan")
    ntoken = MCP.Tokens.mint(lobby, nolan)
    refused = call(ntoken, handshake(ntoken), 2, "advance_stage", %{"thread_id" => workline.id})
    assert refused["isError"]
    assert hd(refused["content"])["text"] =~ "lead"
    assert %Thread{stage: "build"} = Repo.get!(Thread, workline.id)

    pushed = call(ntoken, handshake(ntoken), 3, "push_branch", %{"thread_id" => workline.id})
    assert pushed["isError"] and hd(pushed["content"])["text"] =~ "lead"
  end

  test "the librarian's tools over the wire: a stated fact is refused, a proposal is listed, no judge says so" do
    {:ok, ws} =
      Server.Workspaces.register(%{name: "Stacks", roster: [%{"archetype" => "librarian", "name" => "quain"}]})

    {:ok, thread} = Channel.open_thread(%{title: "sweep", workspace_id: ws.id})
    bank = &Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", provenance: &2, text: &1})
    {:ok, stated} = bank.("never push to main", "stated")
    {:ok, old} = bank.("x is 1", "derived")
    {:ok, new} = bank.("x is 2", "derived")

    {:ok, e} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: "supersede_proposed",
        correlation: "fact:#{new.id}",
        detail: %{"old" => old.id, "verdict" => "supersedes", "reason" => "x changed", "how" => "judge"}
      })

    quain = Staff.agent_by_name("quain")
    token = MCP.Tokens.mint(thread, quain)
    session = handshake(token)

    refused = call(token, session, 2, "supersede_fact", %{"old_id" => stated.id, "new_id" => new.id, "reason" => "old"})
    assert refused["isError"]
    assert hd(refused["content"])["text"] =~ "stated"

    assert [%{"event_id" => id, "new" => %{"text" => "x is 2"}, "old" => %{"text" => "x is 1"}}] =
             decode_tool_json(call(token, session, 3, "review_proposals", %{}))

    assert id == e.id

    # a module with no apply_proposal/1 stands in for a server without the judge
    Application.put_env(:server, :supersede_judge, Server.MCP.ServerTest)
    on_exit(fn -> Application.delete_env(:server, :supersede_judge) end)
    undecided = call(token, session, 4, "decide_proposal", %{"event_id" => e.id, "decision" => "apply"})
    assert undecided["isError"]
    assert hd(undecided["content"])["text"] =~ "isn't installed"
    assert Repo.get!(Fact, new.id).supersedes == nil
  end

  test "write_note defaults to the bound thread; get_notes reads it back" do
    {:ok, thread} = Channel.open_thread(%{title: "notes thread"})
    {:ok, agent} = Staff.register_agent(%{name: "Noter", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    call(token, session, 2, "write_note", %{"body" => "leads are managers"})
    [note] = token |> call(session, 3, "get_notes", %{}) |> decode_tool_json()
    assert note["body"] == "leads are managers"
    assert note["scope"] == "thread"
    assert note["scope_id"] == thread.id
  end

  test "presence_doing tags the declared turn with the tool running, and clears with no what" do
    {:ok, thread} = Channel.open_thread(%{title: "busy thread"})
    {:ok, agent} = Staff.register_agent(%{name: "Doer", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)
    on_exit(fn -> Server.Presence.Thinking.idle(thread.id, "Doer") end)

    call(token, session, 2, "presence_thinking", %{})
    refute call(token, session, 3, "presence_doing", %{"what" => "edit"})["isError"]
    assert [%{doing: "edit"}] = Server.Presence.Thinking.thinking_for(thread.id)
    call(token, session, 4, "presence_doing", %{})
    assert [%{doing: nil}] = Server.Presence.Thinking.thinking_for(thread.id)
  end

  test "presence_doing with a summary lands on the thread's activity feed, as do posts" do
    {:ok, thread} = Channel.open_thread(%{title: "busy thread"})
    {:ok, agent} = Staff.register_agent(%{name: "Doer", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    refute call(token, session, 2, "presence_doing", %{"what" => "test", "summary" => "Bash · mise run check"})[
             "isError"
           ]

    call(token, session, 3, "post_message", %{"body" => "green\nmore detail"})

    assert [
             %{agent: "Doer", kind: "test", summary: "Bash · mise run check"},
             %{kind: "post", summary: "Post · green"}
           ] = Server.Presence.Thinking.activity(thread.id)
  end

  defp bank!(thread, text) do
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: "derived"})
    fact
  end

  defp cited_fact_ids(thread) do
    from(e in Server.Event, where: e.thread_id == ^thread.id and e.kind == "cited", select: e.correlation)
    |> Repo.all()
    |> Enum.map(fn "fact:" <> id -> String.to_integer(id) end)
  end

  defp handshake(token) do
    {200, headers, _} = post(token, nil, initialize_request())
    session = header(headers, "mcp-session-id")
    post(token, session, notification("notifications/initialized"))
    session
  end

  defp call(token, session, id, tool, arguments) do
    {200, _, %{"result" => result}} =
      post(
        token,
        session,
        request(id, "tools/call", %{"name" => tool, "arguments" => arguments})
      )

    result
  end

  # A tool that replies JSON does so as text content; decode the first text blob.
  defp decode_tool_json(%{"content" => content}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    JSON.decode!(text)
  end

  defp initialize_request do
    request(1, "initialize", %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "funes-test", "version" => "0.0.0"}
    })
  end

  defp request(id, method, params \\ nil) do
    then(
      %{"jsonrpc" => "2.0", "id" => id, "method" => method},
      &if(params, do: Map.put(&1, "params", params), else: &1)
    )
  end

  defp notification(method) do
    %{"jsonrpc" => "2.0", "method" => method}
  end

  defp post(token, session, body) do
    headers =
      [{~c"accept", ~c"application/json, text/event-stream"}] ++
        if(token, do: [{~c"authorization", String.to_charlist("Bearer " <> token)}], else: []) ++
        if session, do: [{~c"mcp-session-id", String.to_charlist(session)}], else: []

    {:ok, {{_http, status, _reason}, resp_headers, resp_body}} =
      :httpc.request(
        :post,
        {Process.get(:mcp_url), headers, ~c"application/json", JSON.encode!(body)},
        [],
        body_format: :binary
      )

    {status, resp_headers, decode_body(resp_headers, resp_body)}
  end

  # A StreamableHTTP response is JSON or a one-shot SSE stream; accept both.
  defp decode_body(headers, body) do
    content_type = to_string(header(headers, "content-type") || "")

    cond do
      body in [nil, "", []] ->
        nil

      String.contains?(content_type, "event-stream") ->
        body |> to_string() |> String.split("\n") |> Enum.find_value(&sse_data/1)

      true ->
        JSON.decode!(to_string(body))
    end
  end

  defp sse_data(line) do
    case String.trim_leading(line, "data: ") do
      ^line -> nil
      data -> JSON.decode!(data)
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == name, do: to_string(v)
    end)
  end

  test "consult_oracle asks the OTHER bucket's CLI and posts the exchange to the thread as `oracle`",
       %{token: token, thread: thread} do
    # Carl is not a Claude-plan agent, so the oracle is the Claude side; its CLI is stubbed with
    # echo, which prints its argv back — so the answer carries the prompt we sent.
    previous = Application.get_env(:server, :oracle_claude_cmd)
    Application.put_env(:server, :oracle_claude_cmd, "echo")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:server, :oracle_claude_cmd, previous),
        else: Application.delete_env(:server, :oracle_claude_cmd)
    end)

    session = handshake(token)

    result =
      call(token, session, 40, "consult_oracle", %{"question" => "is SQLite enough here?", "context" => "one operator"})

    assert result["isError"] != true
    %{"side" => "claude", "answer" => answer} = decode_tool_json(result)
    assert answer =~ "is SQLite enough here?"
    assert answer =~ "--model opus"

    posted = Channel.recent_messages(thread, 5)
    assert Enum.any?(posted, &(&1.author == "oracle" and &1.body =~ "asked (claude)"))
  end
end
