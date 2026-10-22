defmodule Server.VerifyTrain do
  @moduledoc """
  A verify train: worklines waiting at `verify` in one repo, stacked and checked once, as the merge
  queue's train lands them (`Server.Workline.land_train/3`), so N verifies cost one full check, not N.

  Each car's own rules run first, alone (`workline-verify.sh` with `RULES_ONLY`, which sends a car
  that breaks them back to build itself). The cars that pass are stacked on `train/<slug>` refs
  (`Server.Workline.Merge.stack/3`, every `work/` branch left as it is) and the last, holding them
  all, gets the full check once; a red is run again before it is believed. Green: each car gets its
  verify evidence (a `check_passed` correlated `workline:<slug>:verify`) and advances. Red twice, a car
  that won't stack, or fewer than two cars left: `:alone`, and the lead verifies by itself while the
  others keep their own turns, so a culprit is found alone. A train only ever skips a check: each car
  is checked again on its own tree when it lands.

  `{:trained, ids}` | `:alone` | `:done` (the lead broke its own rules and was sent back). Opts swap
  the pieces in tests: `merge`, `gate`, `rules`, `advance`, `repo`.
  """
  alias Server.{Repo, Thread, Workline}

  @cars 4

  @doc "How many worklines one train carries at most."
  def cars, do: @cars

  def run(%Thread{} = lead, others, opts \\ []) do
    cars = [lead | others] |> Enum.filter(&at_verify?/1) |> Enum.take(@cars)
    rules = Keyword.get(opts, :rules, &rules/1)

    with [_, _ | _] <- cars,
         passed = Enum.filter(cars, &(rules.(&1) == :ok)),
         {:lead, true} <- {:lead, Enum.any?(passed, &(&1.id == lead.id))},
         [_, _ | _] <- passed,
         {:ok, _} <- stack(passed, opts) do
      {:trained, Enum.map(passed, &ride(&1, passed, opts))}
    else
      {:lead, false} -> :done
      _ -> :alone
    end
  end

  defp stack(cars, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    repo = Keyword.get_lazy(opts, :repo, fn -> Server.Workline.Artifacts.Git.root(hd(cars)) end)
    last = List.last(cars)
    label = "##{last.id} verify train of #{length(cars)}"
    gate = Keyword.get(opts, :gate, &Server.Jobs.Land.gate_train(last, &1, &2, label))
    go = fn -> merger.stack(repo, Enum.map(cars, & &1.slug), gate: gate) end
    with {:error, {:gate, _}} <- go.(), do: go.()
  end

  defp ride(car, cars, opts) do
    advance = Keyword.get(opts, :advance, &Workline.advance/1)
    with_ = cars |> Enum.reject(&(&1.id == car.id)) |> Enum.map_join(", ", &"##{&1.id}")

    {:ok, _} =
      Server.Dossier.record_check(%{
        thread_id: car.id,
        cmd: "mise run check",
        exit: 0,
        tail: "verified in a train with #{with_}: one full check on the stacked cars",
        correlation: "workline:#{car.slug}:verify"
      })

    with %Thread{stage: "verify"} = t <- Repo.get(Thread, car.id), do: advance.(t)
    car.id
  end

  defp at_verify?(%Thread{stage: "verify", state: "open", awaiting: nil}), do: true
  defp at_verify?(_thread), do: false

  # the car's own rules, alone, in its own throwaway checkout: what the stacked check can't judge
  defp rules(car) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")

    with {:ok, tree} <- Server.worktree_for_thread(car),
         {_, 0} <-
           System.cmd("bash", [script, to_string(car.id), car.slug, tree],
             env: [{"RULES_ONLY", "1"}],
             stderr_to_stdout: true
           ) do
      :ok
    else
      _ -> :red
    end
  end
end
