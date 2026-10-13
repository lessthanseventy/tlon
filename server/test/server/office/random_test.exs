defmodule Server.Office.RandomTest do
  # #random: now and then a coworker posts a joke, a pun or an office meme there, written by the
  # banter's cheap tier while an office watches. It is chatter: it never wakes a pane.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Message
  alias Server.Office.Random
  alias Server.Repo
  alias Server.Staff
  alias Server.Switchboard

  setup do
    Server.TestDB.clean!()
    path = Path.join(System.tmp_dir!(), "random-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "tertius", archetype: "surveyor"})
    %{ws: ws}
  end

  defp posts(thread_id), do: Repo.all(from m in Message, where: m.thread_id == ^thread_id)

  defp model(reply) do
    dir = Path.join(System.tmp_dir!(), "random-model-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    File.write!(cli, "#!/bin/sh\necho '#{reply}'\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :banter_cmd, cli)

    on_exit(fn ->
      Application.delete_env(:server, :banter_cmd)
      File.rm_rf!(dir)
    end)
  end

  test "#random is the workspace's own channel and thread, opened on first ask, led by nobody", %{ws: ws} do
    thread = Random.thread(ws.id)
    assert %{name: "random", kind: "topic"} = Server.Channels.get(thread.channel_id)
    assert thread.title == "random" and thread.agent_id == nil and thread.workspace_id == ws.id
    assert Random.thread(ws.id).id == thread.id
    refute Enum.any?(Server.Office.Room.triage(ws.id).unled.shown, &(&1.thread_id == thread.id))
  end

  test "a #random post wakes nobody, not even a coworker it names who leads the thread and is live on it", %{ws: ws} do
    Application.put_env(:server, :arbiter, Server.Arbiter.Test)
    Application.put_env(:server, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)

    thread = Random.thread(ws.id)
    {:ok, yu} = Staff.register_agent(%{name: "yu", mandate: "reviewer", engine: "fresh"})
    {:ok, _} = Staff.assign(thread, yu)
    {:ok, _} = Staff.start_session(%{agent_id: yu.id, thread_id: thread.id, pane_ref: "wYu"})

    {:ok, m} = Random.post(ws.id, "tertius", "@yu why do surveyors never get lost? @andrew knows")

    assert %Message{kind: "notice", delivered_at: %DateTime{}, author: "tertius", body: body} = m
    refute body =~ "@"
    Switchboard.deliver(m)
    Switchboard.drain()
    refute_received {:woke, _, _}
    assert Enum.all?(Server.Office.Needs.list(), &(&1.thread_id != thread.id))
  end

  test "the office asking posts now and then, in a crew member's voice, then waits out the interval", %{ws: ws} do
    model(~s({"post": "git blame: the only tool that tells the truth about this office"}))
    start_supervised!(Random)

    Random.nudge(ws.id)
    tid = Random.thread(ws.id).id

    # the write takes the office's snapshot (Banter.context), slow under a loaded suite
    assert [%Message{author: "tertius", body: "git blame: the only tool" <> _}] =
             Enum.find_value(1..200, fn _ ->
               Process.sleep(50)
               p = posts(tid)
               p != [] && p
             end)

    Random.nudge(ws.id)
    Process.sleep(200)
    assert length(posts(tid)) == 1
  end

  test "pencils down or the banter off, nothing is posted", %{ws: ws} do
    model(~s({"post": "a joke"}))
    start_supervised!(Random)

    :ok = Server.OperatorConfig.put("pause", "pencils_down")
    Random.nudge(ws.id)
    Process.sleep(200)

    :ok = Server.OperatorConfig.put("pause", nil)
    :ok = Server.OperatorConfig.put("banter", false)
    Random.nudge(ws.id)
    Process.sleep(200)

    assert posts(Random.thread(ws.id).id) == []
  end

  test "a post is the model's text, trimmed and kept short; nothing usable is nil" do
    assert Random.parse(~s(sure {"post": "  a pun  "})) == "a pun"
    assert Random.parse(~s({"post": ""})) == nil
    assert Random.parse("no json") == nil
    assert String.length(Random.parse(~s({"post": "#{String.duplicate("x", 900)}"}))) <= 400
  end
end
