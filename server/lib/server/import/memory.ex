defmodule Server.Import.Memory do
  @moduledoc """
  Claude Code's memory files (`~/.claude/projects/*/memory/*.md`) as facts on a project, so every
  coworker on that project recalls what the operator's own Claude sessions learned. A current
  memory has frontmatter (`name`, `description`, `metadata.type`) and a body; an older one is plain
  markdown, named by its folder and file (a new-style `MEMORY.md` is an index and is skipped). The
  facts hang off the project's closed `Claude Code memory` thread (a fact is scoped by its thread),
  keyed by intent `memory:<name>`: a re-import banks nothing twice and carries an edited file's new
  text.

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

  @doc """
  One memory file → `%{name, type, text}`, or nil for an index or a frontmatter with no `name`.
  """
  def parse(path) do
    content = File.read!(path)

    case Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, content) do
      [_, front, body] -> with_frontmatter(front, body)
      nil -> plain(path, content)
    end
  end

  defp with_frontmatter(front, body) do
    case Regex.run(~r/^name:\s*(.+)$/m, front) do
      [_, name] ->
        %{
          name: String.trim(name),
          type: field(front, "type"),
          text: cap("#{field(front, "description")}\n\n#{String.trim(body)}")
        }

      nil ->
        nil
    end
  end

  # An older memory is plain markdown, named by its folder (`-home-andrew-projects-x`) and file,
  # since one folder's MEMORY.md is its notes. A new-style MEMORY.md is only an index of links.
  defp plain(path, content) do
    if !index?(content) do
      folder = path |> Path.dirname() |> Path.dirname() |> Path.basename()
      %{name: "#{folder}/#{Path.basename(path, ".md")}", type: nil, text: cap(content)}
    end
  end

  defp index?(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.all?(&(String.starts_with?(&1, "#") or String.starts_with?(&1, "- [")))
  end

  defp cap(text) do
    text = String.trim(text)
    if String.length(text) > @text_cap, do: String.slice(text, 0, @text_cap) <> " …", else: text
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
