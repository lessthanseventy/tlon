defmodule Server.Recall.CutoverTest do
  # The forgetting-engine write hook (design: docs/plans/2026-08-19-funes-forgetting-design.md):
  # `embed_on_write/1` embeds a freshly-banked fact OFF the write path. It is a side effect on the
  # write result — never load-bearing — so it must return the fact untouched and never raise, even
  # when the embedder is unreachable (the async task swallows that; the caller never sees it).
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Recall

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "t"})
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "x", provenance: "derived"})
    %{fact: fact}
  end

  test "returns the fact unchanged and never blocks or raises", %{fact: fact} do
    # The embedder runs under Server.TaskSupervisor; whether ollama is up or down, this call returns
    # the fact synchronously — a slow/absent embedder can't fail or stall bank_fact.
    assert Recall.embed_on_write(fact) == fact
  end
end
