defmodule Server.Import.Memory do
  @moduledoc """
  Claude Code's memory files (`~/.claude/projects/*/memory/*.md`: frontmatter `name`,
  `description`, `metadata.type`, then a body) as facts on a project, so every coworker on that
  project recalls what the operator's own Claude sessions learned. The facts hang off the
  project's closed `Claude Code memory` thread (a fact is scoped by its thread), keyed by intent
  `memory:<name>`: a re-import banks nothing twice and carries an edited file's new text.

  All `derived` — they rank against the brief's budget instead of pinning into every brief. A
  `feedback`/`user` memory is a `constraint`, the rest `learned`.
  """
  import Ecto.Query

  alias Server.Dossier
  alias Server.Fact
  alias Server.Project
  alias Server.Repo
  alias Server.Thread

  @thread_title "Claude Code memory"
  # a brief's budget is a few thousand tokens; one memory must not be able to eat it
  @text_cap 2_000

  @doc "Import memory files onto `project`. `{:ok, %{banked: n, updated: n}}`."
  def import_files(paths, %Project{} = project) do
    thread = memory_thread(project)

    paths
    |> Enum.map(&parse/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{banked: 0, updated: 0}, fn memory, tally ->
      case upsert(memory, thread) do
        :banked -> Map.update!(tally, :banked, &(&1 + 1))
        :updated -> Map.update!(tally, :updated, &(&1 + 1))
        :same -> tally
      end
    end)
    |> then(&{:ok, &1})
  end

  @doc "One memory file → `%{name, type, text}`, or nil without a `name` in its frontmatter."
  def parse(path) do
    with [_, front, body] <- Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, File.read!(path)),
         [_, name] <- Regex.run(~r/^name:\s*(.+)$/m, front) do
      description = field(front, "description")
      text = String.trim("#{description}\n\n#{String.trim(body)}")

      %{
        name: String.trim(name),
        type: field(front, "type"),
        text: if(String.length(text) > @text_cap, do: String.slice(text, 0, @text_cap) <> " …", else: text)
      }
    else
      _ -> nil
    end
  end

  defp field(front, key) do
    case Regex.run(~r/^\s*#{key}:\s*(.+)$/m, front) do
      [_, value] -> value |> String.trim() |> String.trim("\"")
      nil -> nil
    end
  end

  defp memory_thread(%Project{} = project) do
    Repo.one(from t in Thread, where: t.project_id == ^project.id and t.title == @thread_title, limit: 1) ||
      Repo.insert!(%Thread{
        title: @thread_title,
        state: "closed",
        scope: "machine",
        workspace_id: project.workspace_id,
        project_id: project.id,
        created_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
  end

  defp upsert(memory, thread) do
    intent = "memory:" <> memory.name

    case Repo.get_by(Fact, intent: intent) do
      nil ->
        {:ok, _} =
          Dossier.bank_fact(%{
            thread_id: thread.id,
            intent: intent,
            kind: kind(memory.type),
            provenance: "derived",
            text: memory.text
          })

        :banked

      %Fact{text: text} when text == memory.text ->
        :same

      %Fact{} = fact ->
        fact |> Ecto.Changeset.change(text: memory.text, thread_id: thread.id) |> Repo.update!()
        :updated
    end
  end

  defp kind(type) when type in ["feedback", "user"], do: "constraint"
  defp kind(_type), do: "learned"
end
