defmodule Server.SearchTest do
  # Total recall (design: funes-total-recall) slice A — FTS5 search over the message channel and
  # the fact corpus, so a successor can SEARCH past sessions, not only read the curated brief. The
  # index is external-content FTS5 kept in sync by triggers; every assertion reads back through it.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Repo
  alias Server.Search

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "search subject"})
    %{thread: thread}
  end

  describe "history/2 — FTS over the message channel" do
    test "finds a message by a word in its body, ranked, with a snippet + its count", %{thread: thread} do
      {:ok, _} =
        Channel.post(%{thread_id: thread.id, author: "andrew", body: "the exqlite busy_timeout is set via a NIF"})

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "glm-5.2", body: "unrelated chatter about lunch"})

      %{shown: shown, more: more} = Search.history("busy_timeout")
      assert length(shown) == 1
      assert hd(shown).author == "andrew"
      # Postgres tokenises busy_timeout as two words and marks each; the snippet carries both
      assert hd(shown).snippet =~ "busy" and hd(shown).snippet =~ "timeout"
      assert hd(shown).thread_id == thread.id
      assert more == 0
    end

    test "keeps the index in sync when a message is deleted (the sync triggers)", %{thread: thread} do
      {:ok, msg} = Channel.post(%{thread_id: thread.id, author: "a", body: "ephemeral plan text"})
      assert %{shown: [_]} = Search.history("ephemeral")
      Repo.delete!(msg)
      assert %{shown: []} = Search.history("ephemeral")
    end

    test "a multi-word query ANDs the terms", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "elixir supervision tree design"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "elixir only, no second term here"})

      %{shown: shown} = Search.history("elixir supervision")
      assert length(shown) == 1
    end

    test "special characters in the query don't crash FTS5", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "a normal message"})
      assert %{shown: _} = Search.history(~s("weird -query* AND OR))
    end

    test "an empty/whitespace query returns nothing, not an error" do
      assert %{shown: [], more: 0} = Search.history("   ")
    end
  end

  describe "facts/2 — FTS over the fact corpus" do
    test "finds a banked fact by a word in its text" do
      {:ok, _} =
        Dossier.bank_fact(%{kind: "learned", text: "raxol supports embedding via a PTY", provenance: "derived"})

      {:ok, _} = Dossier.bank_fact(%{kind: "learned", text: "an unrelated conclusion", provenance: "derived"})

      %{shown: shown, more: more} = Search.facts("embedding")
      assert length(shown) == 1
      assert hd(shown).text =~ "embedding"
      assert more == 0
    end
  end
end
