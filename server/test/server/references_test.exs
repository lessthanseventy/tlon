defmodule Server.ReferencesTest do
  # `#42` in a post cites thread 42; the brief resolves it. Pure parse + one lookup.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.References

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "thread_ids/1 finds #N citations, not URL fragments, headings or hex" do
    assert References.thread_ids("see #42 and #7, not https://x/#frag or ##title or a1#3") == [42, 7]
    assert References.thread_ids("#42 twice #42") == [42]
    assert References.thread_ids(nil) == []
  end

  test "cited/2 resolves known threads with title and lead, drops unknown ids and self" do
    {:ok, a} = Channel.open_thread(%{title: "the cited one"})
    {:ok, b} = Channel.open_thread(%{title: "the citing one"})
    messages = [%{body: "as decided in ##{a.id}, and see ##{b.id} (me) and #999999"}]
    assert [%{id: id, title: "the cited one", lead: _}] = References.cited(messages, b.id)
    assert id == a.id
    assert References.cited([%{body: "nothing here"}]) == []
  end
end
