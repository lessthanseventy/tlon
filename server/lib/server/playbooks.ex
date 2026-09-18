defmodule Server.Playbooks do
  @moduledoc """
  The playbooks context: define, list, get, edit, and PROMOTE — a solved thread becomes a
  procedure other coworkers inherit (Multica's compound skills). Every write announces on the
  Bus so a surface listing playbooks refreshes. The seed can carry baseline playbooks the same
  way it carries facts (intent-keyed), so they survive a wipe.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Dossier
  alias Server.Playbook
  alias Server.Repo
  alias Server.Thread

  @doc "Define a playbook. `{:ok, playbook}` or `{:error, changeset}` (bad name, duplicate, no steps)."
  def define(attrs) do
    attrs |> Playbook.define_changeset() |> Repo.insert() |> Bus.announce(:playbook_defined)
  end

  @doc "Every playbook, by name."
  def list, do: Repo.all(from p in Playbook, order_by: [asc: p.name])

  @doc "A playbook by name, or nil."
  def get_by_name(name) when is_binary(name), do: Repo.get_by(Playbook, name: name)

  @doc "Edit steps/summary/success. `{:ok, playbook}` or `{:error, changeset}`."
  def edit(%Playbook{} = playbook, attrs) do
    playbook |> Playbook.edit_changeset(attrs) |> Repo.update() |> Bus.announce(:playbook_edited)
  end

  @doc """
  Promote a thread's solved work into a playbook: its DONE todos become the steps (in the order
  they were done) and its passed CHECKS' commands the success criteria — unless the caller
  supplies `steps`/`success` outright. `{:ok, playbook}` or `{:error, changeset | :nothing_to_promote}`.
  """
  def promote(%Thread{} = thread, attrs) do
    attrs = atomize(attrs)
    steps = attrs[:steps] || steps_from(thread)

    if steps in [nil, ""] do
      {:error, :nothing_to_promote}
    else
      define(%{
        name: attrs[:name],
        summary: attrs[:summary] || thread.title,
        steps: steps,
        success: attrs[:success] || success_from(thread),
        author: attrs[:author],
        source_thread_id: thread.id
      })
    end
  end

  # MCP hands string keys, the CLI atoms; one shape past this line
  defp atomize(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp steps_from(thread) do
    thread
    |> Dossier.done_todos_for_thread()
    # done in the same second is common (a burst of complete_todo); the id breaks the tie in
    # the order the steps were written, which is the order they were done
    |> Enum.sort_by(&{DateTime.to_unix(&1.done_at), &1.id})
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {t, i} -> "#{i}. #{t.text}" end)
  end

  defp success_from(thread) do
    thread
    |> Dossier.recent_checks_for_thread()
    |> Map.get(:shown, [])
    |> Enum.filter(&(&1.kind == "check_passed"))
    |> Enum.map(&get_in(&1.detail, ["cmd"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map_join("\n", &"- `#{&1}` passes")
  end
end
