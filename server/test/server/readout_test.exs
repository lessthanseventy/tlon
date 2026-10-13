defmodule Server.ReadoutTest do
  # `tlon-cli read` / `message`: a thread or a message as plain text, for a terminal or an agent.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Readout

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "the lobby"})
    %{thread: thread}
  end

  test "a thread's last n messages, oldest first, each body whole", %{thread: thread} do
    for body <- ["one", "two", "three\nand a second line"],
        do: {:ok, _} = Channel.post(%{thread_id: thread.id, author: "ada", body: body})

    text = Readout.thread(thread.id, 2)
    assert text =~ "thread ##{thread.id} the lobby (open) · last 2 of 3"
    refute text =~ "one"
    assert text =~ ~r/#\d+ ada · chat · \d{4}-\d\d-\d\d \d\d:\d\d\n  two/
    assert text =~ "  three\n  and a second line"
    assert :binary.match(text, "two") < :binary.match(text, "three")
  end

  test "a message in full: who, what kind, where it points, how it was delivered and resolved", %{thread: thread} do
    {:ok, ask} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "which one?"})

    {:ok, m} =
      Channel.post(%{
        thread_id: thread.id,
        author: "tlon",
        kind: "prompt",
        reply_to: ask.id,
        body: "Do you want to proceed?",
        payload: %{"window" => "t144"}
      })

    text = Readout.message(m.id)
    assert text =~ "message ##{m.id} on thread ##{thread.id} the lobby"
    assert text =~ "tlon · prompt · "
    assert text =~ "reply to ##{ask.id}"
    assert text =~ "delivered: not yet"
    assert text =~ "resolved: no"
    assert text =~ ~s("window":"t144")
    assert text =~ "\nDo you want to proceed?"
  end

  test "an id that isn't there says so" do
    assert Readout.thread(999_999, 5) == "no thread #999999"
    assert Readout.message(999_999) == "no message #999999"
  end
end
