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

  @port 48_631
  @url ~c"http://127.0.0.1:48631/mcp"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: :streamable_http})

    start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: @port})

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
               "bank_fact",
               "raise_issue",
               "record_done",
               "add_todo",
               "complete_todo",
               "raise_question",
               "resolve_question",
               "record_check",
               "recheck_fact",
               "track_thread",
               "open_thread",
               "close_thread",
               "staff_child",
               "assign_lead",
               "switch_thread",
               "consult_peer",
               "spawn_crew",
               "kill_crew",
               "presence_thinking",
               "presence_idle",
               "propose_habit",
               "get_brief",
               "get_dossier",
               "get_facts",
               "get_messages",
               "search_history",
               "search_facts",
               "machine_overview",
               "register_workspace",
               "list_workspaces",
               "edit_workspace",
               "remove_workspace",
               "register_project",
               "file_ticket",
               "list_tickets",
               "update_ticket",
               "write_note",
               "get_notes"
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

  test "track_thread — this connection's thread promotes into the stage machine (slice B)",
       %{thread: thread, token: token} do
    session = handshake(token)
    call(token, session, 3, "register", %{})

    result = call(token, session, 4, "track_thread", %{})
    refute result["isError"]
    assert %{"stage" => "build", "slug" => "review-pr-329"} = decode_tool_json(result)
    assert Repo.get!(Thread, thread.id).stage == "build"

    # Idempotent over the wire — the harness hooks fire it on every commit.
    again = call(token, session, 5, "track_thread", %{})
    refute again["isError"]
    assert decode_tool_json(again)["slug"] == "review-pr-329"
  end

  test "track_thread refuses the ROOT machine thread", %{token: _token} do
    {:ok, root} = Channel.open_thread(%{title: "machine root", scope: "machine"})
    {:ok, agent} = Staff.register_agent(%{name: "tertius-machine", mandate: "survey", engine: "local"})
    token = MCP.Tokens.mint(root, agent)

    session = handshake(token)
    result = call(token, session, 3, "track_thread", %{})

    assert result["isError"]
    assert Repo.get!(Thread, root.id).stage == nil
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

    # The staffed thread is exactly what the cockpit's leaf sweep spawns from: a worker lead...
    assert Channel.thread_lead(tid) == "hronir-machine"

    # ...parented at the CALLER's thread, so its close reports up to the manager (Slice 4D)...
    assert Repo.get!(Thread, tid).parent_thread_id == thread.id

    # ...and the brief on the thread (authored by the CALLER — identity from the token, no spoof).
    [first] = Repo.all(from m in Message, where: m.thread_id == ^tid, order_by: m.id)
    assert first.author == "Carl"
    assert first.body =~ "slice by slice"
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

  test "file_ticket lands in the bound thread's workspace; list_tickets reads it back" do
    {:ok, ws} = Server.Workspaces.register(%{name: "TicketWS"})
    {:ok, thread} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "Filer", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)

    filed =
      token |> call(session, 2, "file_ticket", %{"title" => "auth is fucked", "priority" => "high"}) |> decode_tool_json()

    assert %{"id" => id, "status" => "backlog", "priority" => "high"} = filed
    assert is_integer(id)

    listed = token |> call(session, 3, "list_tickets", %{}) |> decode_tool_json()
    assert Enum.any?(listed, &(&1["id"] == id and &1["title"] == "auth is fucked"))
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
    then(%{"jsonrpc" => "2.0", "id" => id, "method" => method}, &if(params, do: Map.put(&1, "params", params), else: &1))
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
        {@url, headers, ~c"application/json", JSON.encode!(body)},
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
end
