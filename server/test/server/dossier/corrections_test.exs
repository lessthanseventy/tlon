defmodule Server.Dossier.CorrectionsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Attention
  alias Server.Channel
  alias Server.Dossier.Corrections
  alias Server.Fact
  alias Server.Message
  alias Server.Repo

  setup do
    {:ok, thread} = Channel.open_thread(%{title: "the gate"})
    %{thread: thread}
  end

  describe "detect/1" do
    test "a terse message carrying a signal is a correction, trimmed" do
      assert {:ok, "don't retry that order"} = Corrections.detect("  don't retry that order \n")
      assert {:ok, _} = Corrections.detect("always run the gate first")
      assert {:ok, _} = Corrections.detect("use ripgrep instead")
      assert {:ok, _} = Corrections.detect("Actually, keep the branch")
      assert {:ok, _} = Corrections.detect("from now on one PR per fix")
    end

    test "an interjection, a task and an essay are not" do
      assert :none = Corrections.detect("no")
      assert :none = Corrections.detect("ship the release")
      assert :none = Corrections.detect("don't " <> String.duplicate("x", 240))
    end
  end

  describe "heard/1" do
    test "the operator's correction is banked stated, pointing at its message, and the thread hears so",
         %{thread: thread} do
      {:ok, message} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "never force-push main"})

      assert {:ok, fact} = Corrections.heard(message)

      fact = Repo.get!(Fact, fact.id)
      assert fact.provenance == "stated"
      assert fact.kind == "constraint"
      assert fact.text == "never force-push main"
      assert fact.message_id == message.id

      notice = Repo.one!(from(m in Message, where: m.thread_id == ^thread.id and m.author == "tlon"))
      assert notice.kind == "notice"
      assert notice.body =~ "banked fact ##{fact.id}"
      assert notice.body =~ "forget-fact #{fact.id}"
    end

    test "the operator's plain words and anyone else's corrections bank nothing", %{thread: thread} do
      {:ok, plain} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "how is the gate looking"})
      {:ok, other} = Channel.post(%{thread_id: thread.id, author: "hronir", body: "never force-push main"})

      assert :none = Corrections.heard(plain)
      assert :none = Corrections.heard(other)
      assert Repo.aggregate(from(f in Fact, where: f.thread_id == ^thread.id), :count, :id) == 0
    end
  end

  describe "Attention.said/3" do
    test "posts as respond/3 does and banks the correction", %{thread: thread} do
      assert {:ok, %Message{} = message} = Attention.said(thread.id, "andrew", "don't merge without the smoke")

      assert %Fact{provenance: "stated"} = Repo.one!(from(f in Fact, where: f.message_id == ^message.id))
    end
  end
end
