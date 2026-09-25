defmodule Server.Import.ClaudeSessions do
  @moduledoc """
  Claude Code's own transcripts (`~/.claude/projects/*/*.jsonl`) as CLOSED threads: each human
  prompt an operator message, each turn's last text reply a `claude-code` message, backdated to
  when it was said. The conversations that built Tlön become its searchable history
  (`search_history`) and, through the memory pass, its facts.

  History never wakes anyone: rows go in directly (no `Channel.post`, no Bus), delivered, on a
  closed and unstaffed thread. Idempotent per session: the thread's first message is a `tlon`
  receipt naming the session id, and a session with a receipt is skipped.
  """

  import Ecto.Query

  alias Server.Message
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread

  # Sessions a program drove (the memory extractor, eval arms, the switchboard's wake) — not a
  # conversation with the operator.
  @machine_openers ["You extract", "You are a strict evaluator", "New message on thread", "ARM:", "[server thread"]
  @body_cap 6_000

  @doc "One transcript → `%{id, cwd, title, started_at, turns}`, or nil when it holds no human prompt."
  def parse(path) do
    entries =
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case JSON.decode(line) do
          {:ok, %{} = e} -> [e]
          _ -> []
        end
      end)

    turns = turns(entries)

    case turns do
      [{:operator, first, _} | _] ->
        if Enum.any?(@machine_openers, &String.starts_with?(first, &1)) do
          nil
        else
          %{
            id: Path.basename(path, ".jsonl"),
            cwd: Enum.find_value(entries, & &1["cwd"]),
            title: Enum.find_value(Enum.reverse(entries), &title/1) || String.slice(first, 0, 60),
            started_at: at(hd(entries)["timestamp"] || Enum.find_value(entries, & &1["timestamp"])),
            turns: turns
          }
        end

      _ ->
        nil
    end
  end

  defp title(%{"type" => "ai-title", "aiTitle" => t}) when is_binary(t), do: t
  defp title(%{"type" => type, "title" => t}) when type in ["ai-title", "custom-title"] and is_binary(t), do: t
  defp title(%{"type" => "summary", "summary" => t}) when is_binary(t), do: t
  defp title(_), do: nil

  # A turn is a human prompt, then the LAST text the assistant wrote before the next prompt — the
  # answer, not the narration between tool calls.
  defp turns(entries) do
    entries
    |> Enum.reduce([], fn e, acc ->
      case {prompt(e), reply(e), acc} do
        {text, _, _} when is_binary(text) -> [{:operator, text, at(e["timestamp"])} | acc]
        {_, text, [{:claude, _, _} | rest]} when is_binary(text) -> [{:claude, text, at(e["timestamp"])} | rest]
        {_, text, [{:operator, _, _} | _]} when is_binary(text) -> [{:claude, text, at(e["timestamp"])} | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp prompt(%{"type" => "user", "message" => %{"role" => "user", "content" => content}} = e) do
    text = text_of(content)

    if e["isMeta"] || e["isSidechain"] || text == "" || String.starts_with?(text, ["<", "[Request interrupted"]),
      do: nil,
      else: text
  end

  defp prompt(_), do: nil

  defp reply(%{"type" => "assistant", "message" => %{"content" => content}} = e) do
    text = text_of(content)
    if e["isSidechain"] || text == "", do: nil, else: text
  end

  defp reply(_), do: nil

  defp text_of(content) when is_binary(content), do: String.trim(content)

  defp text_of(content) when is_list(content) do
    content
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => t} -> [t]
      _ -> []
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp text_of(_), do: ""

  defp at(nil), do: DateTime.truncate(DateTime.utc_now(), :second)

  defp at(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> at(nil)
    end
  end

  @doc """
  Import every transcript under `dir` into `workspace_id`, each onto the project whose repo holds
  its cwd (else the workspace's default project). `{:ok, %{imported: n, skipped: n}}`.
  """
  def import_dir(dir, workspace_id) do
    projects = Projects.in_workspace(workspace_id)
    fallback = Projects.default(workspace_id)

    dir
    |> Path.expand()
    |> Path.join("*/*.jsonl")
    |> Path.wildcard()
    |> Enum.reduce(%{imported: 0, skipped: 0}, fn path, tally ->
      with %{} = session <- parse(path),
           false <- imported?(session.id),
           {:ok, _} <- insert(session, workspace_id, project_for(session.cwd, projects, fallback)) do
        Map.update!(tally, :imported, &(&1 + 1))
      else
        _ -> Map.update!(tally, :skipped, &(&1 + 1))
      end
    end)
    |> then(&{:ok, &1})
  end

  defp receipt(id), do: "↳ imported from Claude Code session #{id}"

  defp imported?(id) do
    Repo.exists?(from m in Message, where: m.author == "tlon" and m.body == ^receipt(id))
  end

  # The deepest repo that contains the cwd, so ~/projects/ficciones/modules/x lands on ficciones.
  defp project_for(nil, _projects, fallback), do: fallback

  defp project_for(cwd, projects, fallback) do
    projects
    |> Enum.flat_map(fn p ->
      for %{"path" => path} <- p.repos || [], not String.contains?(path, "*"), do: {Path.expand(path), p}
    end)
    |> Enum.filter(fn {root, _} -> cwd == root or String.starts_with?(cwd, root <> "/") end)
    |> Enum.max_by(fn {root, _} -> String.length(root) end, fn -> {nil, fallback} end)
    |> elem(1)
  end

  defp insert(session, workspace_id, project) do
    operator = Application.get_env(:server, :operator, "andrew")

    Repo.transaction(fn ->
      thread =
        Repo.insert!(%Thread{
          title: session.title,
          state: "closed",
          scope: "machine",
          born: "operator",
          workspace_id: workspace_id,
          project_id: project && project.id,
          created_at: session.started_at
        })

      rows =
        Enum.map([{:tlon, receipt(session.id), session.started_at} | session.turns], fn {who, body, at} ->
          %{
            thread_id: thread.id,
            author: author(who, operator),
            body: cap(body),
            created_at: at,
            delivered_at: at,
            mirrored: false
          }
        end)

      Repo.insert_all(Message, rows)
      thread
    end)
  end

  defp author(:tlon, _), do: "tlon"
  defp author(:operator, operator), do: operator
  defp author(:claude, _), do: "claude-code"

  defp cap(body) when byte_size(body) <= @body_cap, do: body
  defp cap(body), do: String.slice(body, 0, @body_cap) <> "\n… (cut at import)"
end
