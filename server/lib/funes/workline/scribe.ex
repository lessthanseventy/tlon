defmodule Server.Workline.Scribe do
  @moduledoc """
  Server' own git hand: write + commit ONE file under `work/<slug>/` in the workline root.
  The single door for artifacts funes materializes itself — the reviewer's review.md
  (`Server.Workline.Review`) and a machine-born workline's intent.md at approval. Identical
  content is `:ok` without a commit: already-committed is the point.
  """

  import Ecto.Query

  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Artifacts

  @doc "Write `work/<slug>/<filename>` and commit it. `{:ok, rel_path}` or `{:error, reason}`."
  def commit(slug, filename, body, commit_message) do
    root = Artifacts.Git.root()
    rel = Path.join(["work", slug, filename])
    abs = Path.join(root, rel)

    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, body)

    with {_, 0} <- git(root, ["add", rel]),
         :ok <- commit_if_dirty(root, rel, commit_message) do
      {:ok, rel}
    else
      {:error, _} = error -> error
      {out, _code} -> {:error, "git refused: #{String.slice(out, 0, 200)}"}
    end
  end

  @doc """
  Materialize a MACHINE-BORN workline's intent.md from its breach evidence (the first
  funes-authored message) at operator approval — the approve verb must be one keypress,
  never "hand-author a file the machine owed". Committed-already → `:ok` untouched.
  """
  def materialize_intent(%Thread{slug: slug} = thread) do
    case Artifacts.Git.check(thread, {:file, "intent.md"}) do
      {:ok, _committed} ->
        :ok

      {:error, _absent} ->
        body = "# #{thread.title}\n\n#{evidence(thread)}\n\n(machine-born intent, approved by the operator)\n"

        case commit(slug, "intent.md", body, "workline #{slug}: intent.md (machine-born, operator-approved)") do
          {:ok, _rel} -> :ok
          {:error, _} = error -> error
        end
    end
  end

  # The breach evidence is the flag's plain message — stage briefs/gates/notes are
  # glyph-prefixed by convention, so the first UNPREFIXED funes message is the evidence.
  @process_glyphs ["▶", "⏸", "→", "⚠", "✅"]

  defp evidence(%Thread{id: id, title: title}) do
    from(m in Message, where: m.thread_id == ^id and m.author == "tlon", order_by: [asc: m.id], select: m.body)
    |> Repo.all()
    |> Enum.find(title, fn body -> not String.starts_with?(body, @process_glyphs) end)
  end

  defp commit_if_dirty(root, rel, message) do
    case git(root, ["status", "--porcelain", "--", rel]) do
      {"", 0} ->
        :ok

      {_dirty, 0} ->
        case git(root, ["commit", "-m", message, "--", rel]) do
          {_, 0} -> :ok
          {out, _} -> {:error, "git commit refused: #{String.slice(out, 0, 200)}"}
        end

      {out, _} ->
        {:error, "git status refused: #{String.slice(out, 0, 200)}"}
    end
  end

  defp git(root, args), do: System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
end
