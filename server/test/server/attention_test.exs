defmodule Server.AttentionTest do
  # Waiting is a first-class state (master plan 2026-09-25, piece A): a coworker's permission
  # dialog becomes a `prompt` message the operator answers from the thread. tmux rides the
  # `:tmux_cmd` seam; the pane text is a captured fixture.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Attention
  alias Server.Board
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Switchboard
  alias Server.Workspaces

  @claude File.read!("test/fixtures/panes/claude_permission_prompt.txt")
  @claude_idle File.read!("test/fixtures/panes/claude_idle.txt")

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, thread} = Channel.open_thread(%{title: "orient", scope: "machine", workspace_id: ws.id})
    Application.put_env(:server, :attention_settle_ms, 0)

    on_exit(fn ->
      for k <- [:tmux_cmd, :attention_settle_ms], do: Application.delete_env(:server, k)
    end)

    %{ws: ws, thread: thread}
  end

  # A fake tmux: `windows` is what list-windows prints, the pane shows whatever `:screen` holds
  # (the fake runs in the test process, so Process.put swaps the screen between ticks).
  defp tmux(windows) do
    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      cond do
        "list-windows" in args -> {windows, 0}
        "capture-pane" in args -> {Process.get(:screen, ""), 0}
        true -> {"", 0}
      end
    end)
  end

  defp leaf(thread_id), do: "1\tt#{thread_id}\t#{thread_id}\t\t123\n"

  defp prompts(thread_id) do
    Repo.all(from m in Message, where: m.thread_id == ^thread_id and m.kind == "prompt", order_by: m.id)
  end

  @claude_ask File.read!("test/fixtures/panes/claude_ask_user_question.txt")

  test "Claude Code, live capture (thread #85, 2026-09-25): AskUserQuestion is a dialog too — the question and its numbered options" do
    assert %{harness: "claude", summary: "Should I proceed with the check?", options: options} =
             Attention.detect(@claude_ask)

    assert Enum.map(options, & &1.key) == ~w(1 2 3 4)
    assert %{key: "1", label: "Yes"} in options
  end

  test "a worker's question on a workline at an ungated stage is cleared by the reply; a gate is not" do
    {:ok, verifying} =
      Server.Workline.open(%{title: "finder", slug: "finder-#{System.unique_integer([:positive])}", stage: "verify"})

    {:ok, _} = Attention.ask(verifying.id, "daneri", "how do I attach my check to verify?")
    assert %{awaiting: "andrew"} = Repo.get(Server.Thread, verifying.id)
    {:ok, _} = Attention.respond(verifying.id, "andrew", "verify is the server's job; it passed")
    assert %{awaiting: nil} = Repo.get(Server.Thread, verifying.id)

    # at review with no review.md yet, the reviewer's question is a question: a reply clears it
    {:ok, reviewing} =
      Server.Workline.open(%{title: "review it", slug: "asking-#{System.unique_integer([:positive])}", stage: "review"})

    {:ok, _} = Attention.ask(reviewing.id, "lonnrot", "who commits review.md?")
    {:ok, _} = Attention.respond(reviewing.id, "andrew", "submit_review does")
    assert %{awaiting: nil} = Repo.get(Server.Thread, reviewing.id)
  end

  test "a workline stands at its gate only on a gated stage whose artifact is there" do
    {:ok, gated} =
      Server.Workline.open(%{title: "review it", slug: "gated-#{System.unique_integer([:positive])}", stage: "review"})

    assert Server.Workline.at_gate?(gated, artifacts: Server.TestArtifacts.Present)
    refute Server.Workline.at_gate?(gated, artifacts: Server.TestArtifacts.Missing)
    refute Server.Workline.at_gate?(%{gated | stage: "verify"}, artifacts: Server.TestArtifacts.Present)
  end

  test "respond/3 reopens a closed thread before posting — the one door reopens too", %{thread: t} do
    {:ok, closed} = Channel.close_thread(t)
    assert closed.state == "closed"
    assert {:ok, %Message{}} = Attention.respond(t.id, "andrew", "picking this back up")
    assert Repo.get!(Server.Thread, t.id).state == "open"
  end

  describe "detect/1 — a harness's own dialog, read off the pane" do
    test "Claude Code: the numbered list under its question (the dialog's shape, not a live capture)" do
      assert %{harness: "claude", summary: "Do you want to proceed?", options: options} = Attention.detect(@claude)
      assert Enum.map(options, & &1.key) == ~w(1 2 3)
      assert %{key: "1", label: "Yes"} in options
    end

    test "an idle prompt, a model's own numbered list, and nothing at all are not waiting" do
      assert Attention.detect(@claude_idle) == nil
      assert Attention.detect("Two ways:\n  1. keep it\n  2. drop it\nWhich?\n❯ ") == nil
      assert Attention.detect("") == nil
    end
  end

  describe "tick/1 — the reconcile" do
    test "a waiting pane opens ONE delivered prompt; the pane moving on resolves it", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @claude)

      :ok = Attention.tick(ws.id)
      :ok = Attention.tick(ws.id)

      assert [%Message{author: "tlon", kind: "prompt", resolved_at: nil, delivered_at: %DateTime{}} = p] = prompts(t.id)
      assert p.payload["summary"] == "Do you want to proceed?"
      assert p.payload["window"] == "t#{t.id}"
      assert p.body =~ "⚑ waiting on you — Do you want to proceed?"
      assert Attention.waiting?(t.id)
      assert %{summary: "Do you want to proceed?"} = Attention.open_prompts_by_thread()[t.id]

      Process.put(:screen, @claude_idle)
      :ok = Attention.tick(ws.id)

      assert [%Message{resolution: "answered in the terminal", resolved_at: %DateTime{}}] = prompts(t.id)
      refute Attention.waiting?(t.id)
    end

    test "a tmux that can't list its windows closes no prompt", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)

      Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"server exited unexpectedly", 1} end)
      :ok = Attention.tick(ws.id)
      assert [%Message{resolved_at: nil}] = prompts(t.id)
    end

    test "a new dialog on the same window supersedes; a window that is gone closes its prompt", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)

      Process.put(:screen, @claude_ask)
      :ok = Attention.tick(ws.id)

      assert [%Message{resolution: "superseded"}, %Message{resolved_at: nil} = open] = prompts(t.id)
      assert open.payload["summary"] == "Should I proceed with the check?"

      tmux("")
      :ok = Attention.tick(ws.id)
      assert [_, %Message{resolution: "window closed"}] = prompts(t.id)
    end

    test "the sidebar row carries the open prompt", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)

      row = Board.sidebar() |> Enum.flat_map(& &1.threads) |> Enum.find(&(&1.id == t.id))
      assert %{summary: "Do you want to proceed?", options: [%{"key" => "1"} | _]} = row.prompt
    end
  end

  test "the sweep forgets the limit memory of a pane whose window is gone", %{ws: ws, thread: t} do
    limit = "  ⎿  Claude usage limit reached. Your limit will reset at 5pm (America/Denver)."
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
    seen = fn -> Repo.get!(Server.Workspace, ws.id).knobs["limits_seen"] || %{} end

    Process.put(:screen, limit)
    tmux("1\tt#{t.id}\t#{t.id}\t\t123\thronir\t\n")
    :ok = Attention.tick(ws.id)
    assert Map.keys(seen.()) == ["hronir/#{t.id}/t#{t.id}"]

    Process.put(:screen, "")
    tmux("2\tother\t#{t.id}\t\t123\thronir\t\n")
    :ok = Attention.tick(ws.id)
    assert seen.() == %{}
  end

  test "an empty window list is not read as every pane gone", %{ws: ws, thread: t} do
    limit = "  ⎿  Claude usage limit reached. Your limit will reset at 5pm (America/Denver)."
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})

    Process.put(:screen, limit)
    tmux("1\tt#{t.id}\t#{t.id}\t\t123\thronir\t\n")
    :ok = Attention.tick(ws.id)

    tmux("")
    :ok = Attention.tick(ws.id)
    assert Map.keys(Repo.get!(Server.Workspace, ws.id).knobs["limits_seen"]) == ["hronir/#{t.id}/t#{t.id}"]
  end

  describe "answer_prompt/3 — every answer names its prompt" do
    setup %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)
      [prompt] = prompts(t.id)
      %{prompt: prompt, target: "w#{ws.id}:=t#{t.id}"}
    end

    test "an option key answers: its number pressed, a delivered reply, the prompt resolved",
         %{prompt: prompt, target: target} do
      assert {:ok, reply} = Attention.answer_prompt(prompt.id, "andrew", "1")

      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "1"]}
      refute_receive {:tmux, [_, _, "send-keys", "-t", ^target, "Enter"]}
      assert %Message{kind: "chat", reply_to: reply_to, delivered_at: %DateTime{}} = reply
      assert reply_to == prompt.id
      assert [%Message{resolution: "answered: 1"}] = prompts(prompt.thread_id)
      refute Attention.waiting?(prompt.thread_id)
    end

    test "the label answers too, and text after the key follows as its own burst, then Enter",
         %{ws: ws, thread: t, prompt: prompt, target: target} do
      assert {:ok, _} = Attention.answer_prompt(prompt.id, "andrew", "Yes")
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "1"]}

      :ok = Attention.tick(ws.id)
      [_, again] = prompts(t.id)
      assert {:ok, _} = Attention.answer_prompt(again.id, "andrew", "3 use mise, not a bare mix")
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "3"]}
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "use mise, not a bare mix"]}
      assert_receive {:tmux, [_, _, "send-keys", "-t", ^target, "Enter"]}
    end

    test "a pane dialog is typed into only while the pane still shows it",
         %{prompt: prompt, target: target} do
      Process.put(:screen, @claude_idle)

      assert {:error, :not_showing} = Attention.answer_prompt(prompt.id, "andrew", "1")
      refute_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, _]}
      assert Repo.get!(Message, prompt.id).resolved_at == nil
    end

    test "two open prompts on one thread: answering one by id leaves the other open and untouched",
         %{ws: ws, thread: t, prompt: dialog, target: target} do
      gate = release_gate!(ws, t)

      assert {:ok, reply} = Attention.answer_prompt(gate.id, "andrew", "n")
      assert reply.reply_to == gate.id
      assert Repo.get!(Message, gate.id).resolution == "answered: n"
      refute_receive {:tmux, [_, _, "send-keys" | _]}
      assert %Message{resolved_at: nil} = Repo.get!(Message, dialog.id)

      gate = release_gate!(ws, t)
      assert {:ok, _} = Attention.answer_prompt(dialog.id, "andrew", "1")
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "1"]}
      assert %Message{resolved_at: nil} = Repo.get!(Message, gate.id)
    end

    test "a plain post on the thread is a plain post: no prompt is answered, no key typed, and the switchboard holds it",
         %{thread: t, prompt: prompt, target: target} do
      assert {:ok, %Message{kind: "chat", delivered_at: nil, reply_to: nil} = m} =
               Attention.respond(t.id, "andrew", "1")

      refute_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, _]}
      assert Repo.get!(Message, prompt.id).resolved_at == nil
      assert {:pending, _} = Switchboard.deliver(m)
      assert Attention.waiting?(t.id)
    end

    test "an unknown or answered prompt, or a key it doesn't offer, is refused", %{prompt: prompt} do
      assert {:error, :not_found} = Attention.answer_prompt(-1, "andrew", "1")
      assert {:error, :no_such_option} = Attention.answer_prompt(prompt.id, "andrew", "9")
      assert {:ok, _} = Attention.answer_prompt(prompt.id, "andrew", "1")
      assert {:error, :answered} = Attention.answer_prompt(prompt.id, "andrew", "1")
    end
  end

  # the PM's release gate as `Server.Release.PM` leaves it: a prompt no pane holds
  defp release_gate!(ws, t) do
    %{
      thread_id: t.id,
      author: "tlon",
      body: "⚑ release abc1234",
      kind: "prompt",
      payload: %{
        "release" => "abc1234",
        "workspace_id" => ws.id,
        "summary" => "release abc1234",
        "options" => [%{"key" => "a", "label" => "approve"}, %{"key" => "n", "label" => "not yet"}]
      }
    }
    |> Message.post_changeset()
    |> Repo.insert!()
  end

  describe "ask/4 — a decision with its answers attached" do
    test "an ask is a pane-less prompt per decision: the thread doesn't park, nothing waits in a pane",
         %{thread: t} do
      assert {:ok, a} = Attention.ask(t.id, "tertius", "ireneo's weather: start now?", ["go", "hold"])
      assert {:ok, b} = Attention.ask(t.id, "tertius", "lonnrot's north wall?", ["go", "fold into #172"])

      assert Enum.map(prompts(t.id), & &1.id) == [a.id, b.id]
      assert a.payload["ask"] == "tertius"
      assert a.payload["options"] == [%{"key" => "1", "label" => "go"}, %{"key" => "2", "label" => "hold"}]
      assert Repo.get!(Server.Thread, t.id).awaiting == nil
      refute Attention.waiting?(t.id)
      refute Map.has_key?(Attention.open_prompts_by_thread(), t.id)
    end

    test "answering one by id posts it to the asker and resolves only that ask", %{thread: t} do
      {:ok, a} = Attention.ask(t.id, "tertius", "ireneo's weather: start now?", ["go", "hold"])
      {:ok, b} = Attention.ask(t.id, "tertius", "lonnrot's north wall?", ["go", "fold into #172"])

      assert {:ok, reply} = Attention.answer_prompt(a.id, "andrew", "2")
      assert %Message{author: "andrew", reply_to: reply_to, delivered_at: nil, body: body} = reply
      assert reply_to == a.id
      assert body == "@tertius ireneo's weather: start now? → hold"
      assert Repo.get!(Message, a.id).resolution == "answered: hold"
      assert Repo.get!(Message, b.id).resolved_at == nil
      assert {:error, :answered} = Attention.answer_prompt(a.id, "andrew", "1")
      assert {:error, :no_such_option} = Attention.answer_prompt(b.id, "andrew", "7")
    end

    test "an answer may lead with the label and say more", %{thread: t} do
      {:ok, a} = Attention.ask(t.id, "tertius", "start now?", ["go", "hold"])

      assert {:ok, %Message{body: "@tertius start now? → go — after the cut"}} =
               Attention.answer_prompt(a.id, "andrew", "go after the cut")

      assert Repo.get!(Message, a.id).resolution == "answered: go"
    end

    test "an ask about another thread is withdrawn when that thread closes, and the asker is told",
         %{thread: t} do
      {:ok, about} = Channel.open_thread(%{title: "toy step 1"})
      {:ok, other} = Channel.open_thread(%{title: "still going"})
      {:ok, a} = Attention.ask(t.id, "scharlach", "how should it move?", ["allow", "advance"], about.id)
      {:ok, b} = Attention.ask(t.id, "scharlach", "and this one?", ["go", "hold"], other.id)

      {:ok, _} = Channel.close_thread(about)

      assert Repo.get!(Message, a.id).resolution == "withdrawn: ##{about.id} closed"
      assert Repo.get!(Message, b.id).resolved_at == nil
      assert Enum.map(Attention.open_asks(), & &1.id) == [b.id]

      assert [%Message{author: "tlon", reply_to: reply_to, body: body}] =
               Repo.all(from m in Message, where: m.thread_id == ^t.id and m.kind == "chat")

      assert reply_to == a.id
      assert body =~ "@scharlach"
      assert body =~ "##{about.id} closed"
    end

    test "an ask on a thread is withdrawn when that thread closes, with no note on the closed thread" do
      {:ok, built} = Channel.open_thread(%{title: "#131 streamed usage"})
      {:ok, a} = Attention.ask(built.id, "hladik", "close as no-change?", ["close", "tweak anyway"])

      {:ok, _} = Channel.close_thread(built)

      assert Repo.get!(Message, a.id).resolution == "withdrawn: ##{built.id} closed"
      assert Attention.open_asks() == []
      refute Enum.any?(Channel.thread_messages(built), &(&1.author == "tlon" and &1.body =~ "withdrawn"))
    end

    test "answering by id settles the thread's question, as a reply on it does", %{thread: t} do
      {:ok, _} = t |> Ecto.Changeset.change(awaiting: "andrew") |> Repo.update()
      {:ok, a} = Attention.ask(t.id, "tertius", "start now?", ["go", "hold"])

      assert {:ok, _} = Attention.answer_prompt(a.id, "andrew", "1")
      assert Repo.get!(Server.Thread, t.id).awaiting == nil
    end

    test "an asker gone off shift: the answer goes to the lead on shift, and names who asked", %{ws: ws} do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "otalora", archetype: "builder", crew: "night"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "emma", archetype: "builder", crew: "day"})
      {:ok, built} = Server.Workline.open(%{title: "the small joys", slug: "joys", stage: "build", workspace_id: ws.id})
      {:ok, a} = Attention.ask(built.id, "otalora", "resume the build?", ["resume", "hold"])
      {:ok, _} = Channel.assign_lead(built.id, "emma")

      assert {:ok, %Message{body: body}} = Attention.answer_prompt(a.id, "andrew", "1")
      assert body == "@emma (otalora asked, now off shift) resume the build? → resume"
    end

    test "a lead's ask answered after the thread was handed on goes to the lead it went to", %{ws: ws} do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "pierre", archetype: "builder"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "emma", archetype: "builder"})
      {:ok, built} = Server.Workline.open(%{title: "pet store", slug: "pets", stage: "spec", workspace_id: ws.id})
      {:ok, _} = Channel.assign_lead(built.id, "pierre")
      {:ok, a} = Attention.ask(built.id, "pierre", "replace the old pet?", ["replace", "keep"])
      {:ok, _} = Channel.assign_lead(built.id, "emma")

      assert {:ok, %Message{body: body}} = Attention.answer_prompt(a.id, "andrew", "1")
      assert body == "@emma (pierre asked, no longer leads it) replace the old pet? → replace"
    end

    test "an ask from a thread its asker doesn't lead is answered to the asker", %{ws: ws, thread: t} do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "pierre", archetype: "builder"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius", archetype: "builder"})
      {:ok, _} = Channel.assign_lead(t.id, "tertius")
      {:ok, a} = Attention.ask(t.id, "pierre", "which slot?", ["cat", "dog"])

      assert {:ok, %Message{body: "@pierre which slot? → cat"}} = Attention.answer_prompt(a.id, "andrew", "1")
    end
  end
end
