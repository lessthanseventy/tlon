defmodule Console.PolicyImport do
  @moduledoc """
  One-shot: the coworker knobs that lived in `~/.config/console/config.json` become
  `workspace_policy` rows (UX slice 5). The file was keyed by profile NAME, machine-wide; a policy
  is keyed workspace × agent, so one override lands on every workspace that seats that coworker —
  which is the semantic change, made once and visibly, rather than the file quietly ceasing to
  matter.

  Idempotent and never destructive: a seat that already has a policy is left alone, and the file's
  `coworkers` section is renamed rather than deleted, so the old values stay readable if the
  spread turns out wrong.
  """
  alias Console.Server.Workspaces

  require Logger

  @doc """
  Import if there is anything to import. Returns `{:ok, n}` with the number of policies written,
  or `:noop`. Absorbs its own failures: an import must never be the reason the cockpit won't boot.
  """
  @spec run(String.t()) :: {:ok, non_neg_integer()} | :noop
  def run(path \\ Console.Config.path()) do
    case Console.Config.read(path)["coworkers"] do
      map when is_map(map) and map_size(map) > 0 -> import_all(map, path)
      _ -> :noop
    end
  rescue
    e ->
      Logger.warning("Console.PolicyImport: skipped — #{Exception.message(e)}")
      :noop
  end

  defp import_all(coworkers, path) do
    written =
      for {name, knobs} <- coworkers,
          %{id: ws_id} <- Workspaces.all(),
          seat = Enum.find(Workspaces.bench(ws_id), &(&1.name == name)),
          not is_nil(seat),
          is_nil(Workspaces.policy(ws_id, seat.agent_id)),
          attrs = policy_attrs(knobs),
          attrs != %{},
          reduce: 0 do
        acc ->
          {:ok, _} = Workspaces.set_policy(ws_id, seat.agent_id, attrs)
          acc + 1
      end

    if written > 0 do
      Logger.info("Console.PolicyImport: #{written} coworker override(s) → workspace_policy")
      retire(path)
    end

    {:ok, written}
  end

  # The file's shape → the policy's. `yolo` was the ask-vs-allow default under another name.
  defp policy_attrs(knobs) when is_map(knobs) do
    %{}
    |> put_model(knobs)
    |> put_ask_default(knobs["yolo"])
  end

  defp policy_attrs(_knobs), do: %{}

  defp put_model(attrs, %{"provider" => p, "model" => m} = knobs),
    do: Map.put(attrs, :model, %{"provider" => p, "model" => m, "thinking" => knobs["thinking"] || "medium"})

  defp put_model(attrs, _knobs), do: attrs

  defp put_ask_default(attrs, true), do: Map.put(attrs, :ask_default, "allow")
  defp put_ask_default(attrs, false), do: Map.put(attrs, :ask_default, "ask")
  defp put_ask_default(attrs, _unset), do: attrs

  # Renamed, not deleted: the values stay readable if the per-workspace spread was not what the
  # operator meant, and the rename is what stops a second import.
  defp retire(path) do
    map = Console.Config.read(path)
    retired = map |> Map.delete("coworkers") |> Map.put("coworkers_imported", map["coworkers"])
    Console.Config.write!(retired, path)
  end
end
