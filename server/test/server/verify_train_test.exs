defmodule Server.VerifyTrainTest do
  # A verify train: worklines waiting at verify are stacked and checked once (Server.VerifyTrain).
  # Each car's own rules run first; green, each car gets its evidence and advances; red twice, or
  # too few cars, and the lead verifies alone.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.VerifyTrain
  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  # stack/3 answered from the test process: green unless told otherwise
  defmodule Stack do
    @moduledoc false
    def stack(_repo, slugs, opts) do
      send(self(), {:stack, slugs})

      case Process.get(:stack_results, []) do
        [r | rest] ->
          Process.put(:stack_results, rest)
          r

        [] ->
          with {:ok, _} <- opts[:gate].("repo", "train/#{List.last(slugs)}"),
               do: {:ok, %{from: "m", cars: Enum.map(slugs, &%{slug: &1, to: "to-#{&1}", tree: "tree-#{&1}"})}}
      end
    end
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp at_verify!(slug) do
    {:ok, t} = Workline.open(%{title: slug, slug: slug, stage: "verify"})
    t
  end

  defp opts(extra \\ []) do
    Keyword.merge(
      [
        merge: Stack,
        gate: fn _repo, _ref -> {:ok, :green} end,
        rules: fn _t -> :ok end,
        advance: &Workline.advance(&1, artifacts: AllPresent),
        repo: "repo"
      ],
      extra
    )
  end

  defp evidence(t),
    do:
      Repo.all(
        from(e in Server.Event, where: e.correlation == ^"workline:#{t.slug}:verify" and e.kind == "check_passed")
      )

  test "two at verify ride one check: each gets its evidence and advances" do
    a = at_verify!("va")
    b = at_verify!("vb")

    assert {:trained, ids} = VerifyTrain.run(a, [b], opts())
    assert Enum.sort(ids) == Enum.sort([a.id, b.id])
    assert_received {:stack, ["va", "vb"]}
    refute_received {:stack, _}

    for t <- [a, b] do
      assert [%{detail: %{"exit" => 0}}] = evidence(t)
      assert Repo.get!(Thread, t.id).stage != "verify"
    end
  end

  test "a car that breaks its own rules drops out; with one car left, the lead verifies alone" do
    a = at_verify!("ra")
    b = at_verify!("rb")
    assert :alone = VerifyTrain.run(a, [b], opts(rules: fn t -> if t.id == b.id, do: :red, else: :ok end))
    refute_received {:stack, _}
  end

  test "a lead that breaks its own rules is done: the rules already sent it back" do
    a = at_verify!("la")
    b = at_verify!("lb")
    c = at_verify!("lc")
    assert :done = VerifyTrain.run(a, [b, c], opts(rules: fn t -> if t.id == a.id, do: :red, else: :ok end))
    refute_received {:stack, _}
  end

  test "red is run again before it is believed; red twice and the lead verifies alone, nobody advanced" do
    a = at_verify!("xa")
    b = at_verify!("xb")
    Process.put(:stack_results, [{:error, {:gate, "red"}}, {:error, {:gate, "red"}}])

    assert :alone = VerifyTrain.run(a, [b], opts())
    assert_received {:stack, _}
    assert_received {:stack, _}
    assert evidence(a) == [] and evidence(b) == []
    assert Repo.get!(Thread, b.id).stage == "verify"
  end

  test "one red then green: the flake is not believed, both advance" do
    a = at_verify!("fa")
    b = at_verify!("fb")
    Process.put(:stack_results, [{:error, {:gate, "red"}}])
    assert {:trained, _} = VerifyTrain.run(a, [b], opts())
  end

  test "alone, it is the lead's own verify" do
    assert :alone = VerifyTrain.run(at_verify!("solo"), [], opts())
  end
end
