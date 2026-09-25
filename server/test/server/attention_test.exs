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

  @pi File.read!("test/fixtures/panes/pi_permission_prompt.txt")
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

  test "respond/3 reopens a closed thread before posting — the one door reopens too", %{thread: t} do
    {:ok, closed} = Channel.close_thread(t)
    assert closed.state == "closed"
    assert {:ok, %Message{}} = Attention.respond(t.id, "andrew", "picking this back up")
    assert Repo.get!(Server.Thread, t.id).state == "open"
  end

  describe "detect/1 — a harness's own dialog, read off the pane" do
    test "pi-permission-system: the cursor-marked options and the command it asks about" do
      assert %{harness: "pi", summary: "bash: env", options: options} = Attention.detect(@pi)
      assert Enum.map(options, & &1.key) == ~w(y s n r)
      assert %{key: "s", label: ~s(Yes, allow bash "env" for this session)} in options
    end

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
      Process.put(:screen, @pi)

      :ok = Attention.tick(ws.id)
      :ok = Attention.tick(ws.id)

      assert [%Message{author: "tlon", kind: "prompt", resolved_at: nil, delivered_at: %DateTime{}} = p] = prompts(t.id)
      assert p.payload["summary"] == "bash: env"
      assert p.payload["window"] == "t#{t.id}"
      assert p.body =~ "⚑ waiting on you — bash: env"
      assert Attention.waiting?(t.id)
      assert %{summary: "bash: env"} = Attention.open_prompts_by_thread()[t.id]

      Process.put(:screen, @claude_idle)
      :ok = Attention.tick(ws.id)

      assert [%Message{resolution: "answered in the terminal", resolved_at: %DateTime{}}] = prompts(t.id)
      refute Attention.waiting?(t.id)
    end

    test "a new dialog on the same window supersedes; a window that is gone closes its prompt", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @pi)
      :ok = Attention.tick(ws.id)

      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)

      assert [%Message{resolution: "superseded"}, %Message{resolved_at: nil} = open] = prompts(t.id)
      assert open.payload["summary"] == "Do you want to proceed?"

      tmux("")
      :ok = Attention.tick(ws.id)
      assert [_, %Message{resolution: "window closed"}] = prompts(t.id)
    end

    test "the sidebar row carries the open prompt", %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @pi)
      :ok = Attention.tick(ws.id)

      row = Board.sidebar() |> Enum.flat_map(& &1.threads) |> Enum.find(&(&1.id == t.id))
      assert %{summary: "bash: env", options: [%{"key" => "y"} | _]} = row.prompt
    end
  end

  describe "respond/3 — the operator's one door" do
    setup %{ws: ws, thread: t} do
      tmux(leaf(t.id))
      Process.put(:screen, @pi)
      :ok = Attention.tick(ws.id)
      [prompt] = prompts(t.id)
      %{prompt: prompt, target: "w#{ws.id}:=t#{t.id}"}
    end

    test "an option key answers: pi's letter pressed twice, a delivered reply, the prompt resolved",
         %{thread: t, prompt: prompt, target: target} do
      assert {:ok, reply} = Attention.respond(t.id, "andrew", "y")

      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "yy"]}
      refute_receive {:tmux, [_, _, "send-keys", "-t", ^target, "Enter"]}
      assert %Message{kind: "chat", reply_to: reply_to, delivered_at: %DateTime{}} = reply
      assert reply_to == prompt.id
      assert [%Message{resolution: "answered: y"}] = prompts(t.id)
      refute Attention.waiting?(t.id)
    end

    test "the label answers too, and text after the key follows as its own burst, then Enter",
         %{ws: ws, thread: t, target: target} do
      assert {:ok, _} = Attention.respond(t.id, "andrew", "No, provide reason")
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "rr"]}

      # Claude Code takes the number outright.
      Process.put(:screen, @claude)
      :ok = Attention.tick(ws.id)
      assert {:ok, _} = Attention.respond(t.id, "andrew", "3 use mise, not a bare mix")
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "3"]}
      assert_receive {:tmux, [_, _, "send-keys", "-l", "-t", ^target, "use mise, not a bare mix"]}
      assert_receive {:tmux, [_, _, "send-keys", "-t", ^target, "Enter"]}
    end

    test "anything else is a plain post, and the switchboard holds it while the prompt is open", %{thread: t} do
      assert {:ok, %Message{kind: "chat", delivered_at: nil} = m} =
               Attention.respond(t.id, "andrew", "carry on when done")

      assert {:pending, _} = Switchboard.deliver(m)
      assert Repo.get!(Message, m.id).delivered_at == nil
      assert Attention.waiting?(t.id)
    end
  end
end
