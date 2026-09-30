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

    test "a multi-word query matches ANY term, the message matching more of them first", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "elixir only, no second term here"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "elixir supervision tree design"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "nothing relevant"})

      %{shown: shown, more: 0} = Search.history("elixir supervision")
      assert shown |> Enum.map(& &1.snippet) |> Enum.map(&(&1 =~ "supervision")) == [true, false]
    end

    test "a rare query word outweighs a common one, however often the common one repeats", %{thread: thread} do
      for body <- ["daily standup, daily notes, daily review", "the daily sync ran long daily", "daily daily daily"] do
        {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: body})
      end

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "user", body: "my commute is 45 minutes"})

      assert %{shown: [first | _]} = Search.history("my daily commute")
      assert first.snippet =~ "commute"
    end

    test "around: n gives each hit its conversation, n turns either side from its own thread", %{thread: thread} do
      {:ok, other} = Channel.open_thread(%{title: "elsewhere"})

      for {tid, body} <- [
            {thread.id, "first"},
            {thread.id, "what was the budget again?"},
            {other.id, "noise between"},
            {thread.id, "the budget is 400 dollars"},
            {thread.id, "thanks"},
            {thread.id, "last"}
          ] do
        {:ok, _} = Channel.post(%{thread_id: tid, author: "a", body: body})
      end

      assert %{shown: [hit]} = Search.history("dollars", 10, around: 1)
      assert Enum.map(hit.window, & &1.body) == ["what was the budget again?", "the budget is 400 dollars", "thanks"]
      assert %{shown: [plain]} = Search.history("dollars")
      refute Map.has_key?(plain, :window)
    end

    test "with a query embedding, a message that shares its meaning but no word is found", %{thread: thread} do
      {:ok, car} = Channel.post(%{thread_id: thread.id, author: "user", body: "the automobile needs new brakes"})
      {:ok, lunch} = Channel.post(%{thread_id: thread.id, author: "user", body: "lunch was good"})
      embed!(car, [1.0, 0.0, 0.0])
      embed!(lunch, [0.0, 1.0, 0.0])

      assert %{shown: [first | _]} = Search.history("car trouble", 10, query_embedding: [0.9, 0.1, 0.0])
      assert first.message_id == car.id
    end

    test "a message ranked by both meaning and words beats one ranked by either alone", %{thread: thread} do
      {:ok, both} = Channel.post(%{thread_id: thread.id, author: "a", body: "brakes on the car"})
      {:ok, words} = Channel.post(%{thread_id: thread.id, author: "a", body: "a car wash coupon"})
      {:ok, meaning} = Channel.post(%{thread_id: thread.id, author: "a", body: "the automobile"})
      embed!(both, [0.8, 0.2, 0.0])
      embed!(words, [0.0, 1.0, 0.0])
      embed!(meaning, [1.0, 0.0, 0.0])

      %{shown: shown} = Search.history("car", 10, query_embedding: [1.0, 0.0, 0.0])
      assert hd(shown).message_id == both.id
      assert MapSet.new(shown, & &1.message_id) == MapSet.new([both.id, words.id, meaning.id])
    end

    test "a question in plain words finds the message that answers it", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "user", body: "my commute is 45 minutes each way"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "user", body: "lunch was good"})

      assert %{shown: [hit]} = Search.history("How long is my daily commute to work?")
      assert hit.snippet =~ "commute"
    end

    test "a term with a leading dash is searched for, never read as NOT", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "the supervision tree design"})

      assert %{shown: [_]} = Search.history("-supervision")
      assert %{shown: [_]} = Search.history("tree -supervision")
    end

    test "special characters in the query don't crash FTS5", %{thread: thread} do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "a normal message"})
      assert %{shown: _} = Search.history(~s("weird -query* AND OR))
    end

    test "an empty/whitespace query returns nothing, not an error" do
      assert %{shown: [], more: 0} = Search.history("   ")
    end
  end

  defp embed!(message, vector) do
    message |> Ecto.Changeset.change(embedding: vector, embedding_model: "test") |> Repo.update!()
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

    test "a question in plain words finds the fact that answers it, more matched terms first" do
      {:ok, _} = Dossier.bank_fact(%{kind: "learned", text: "the release runs on port 4040", provenance: "derived"})

      {:ok, _} =
        Dossier.bank_fact(%{kind: "learned", text: "the MCP channel listens on port 4040", provenance: "derived"})

      %{shown: shown, more: 0} = Search.facts("Which port does the MCP channel listen on?")
      assert Enum.map(shown, & &1.text) == ["the MCP channel listens on port 4040", "the release runs on port 4040"]
    end
  end
end
