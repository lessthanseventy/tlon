defmodule Server.Import.ClaudeSessions do
  @moduledoc """
  Claude Code's own transcripts (`~/.claude/projects/*/*.jsonl`) as CLOSED threads: each human
  prompt an operator message, each turn's last text reply a `claude-code` message, backdated to
  when it was said. The conversations that built Tlön become its searchable history
  (`search_history`) and, through the memory pass, its facts. The parser also reads pi's format
  (a `session` header, `message` entries); `Server.Import.PiSessions` points it at `~/.pi`.

  History never wakes anyone: rows go in directly (no `Channel.post`, no Bus), delivered, on a
  closed and unstaffed thread. Idempotent per session: the thread's first message is a `tlon`
  receipt naming the session id, and a session with a receipt is skipped. A thread lands on the
  project and repo whose checkout holds the session's cwd, else the workspace's default project.
  """

  import Ecto.Query

  alias Server.Message
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread

  # Sessions a program drove (the memory extractor, eval arms, the switchboard's wake) — not a
  # conversation with the operator.
  @machine_openers [
    "You extract",
    "You are a strict evaluator",
    "You are reviewing",
    "New message on thread",
    "ARM:",
    "[server thread",
    "[tlon thread",
    "[funes thread",
    "you have "
  ]
  @body_cap 6_000

  @doc """
  One transcript → `%{source, id, cwd, title, started_at, turns}`, or nil when it holds no human
  prompt or a program drove it.
  """
  def parse(path) do
    entries = decode(path)

    case turns(entries) do
      [{:operator, first, _} | _] = turns ->
        if machine?(first) or smoke_test?(turns), do: nil, else: session(path, entries, first, turns)

      _ ->
        nil
    end
  end

  defp decode(path) do
    path
    |> File.stream!()
    |> Enum.flat_map(fn line ->
      case JSON.decode(line) do
        {:ok, %{} = e} -> [e]
        _ -> []
      end
    end)
  end

  defp session(path, entries, first, turns) do
    # pi opens its transcript with a `session` entry; Claude Code has none
    header = Enum.find(entries, &(&1["type"] == "session"))

    %{
      source: if(header, do: :pi, else: :claude_code),
      id: (header && header["id"]) || Path.basename(path, ".jsonl"),
      cwd: Enum.find_value(entries, & &1["cwd"]),
      title: Enum.find_value(Enum.reverse(entries), &title/1) || String.slice(first, 0, 60),
      started_at: at(hd(entries)["timestamp"] || Enum.find_value(entries, & &1["timestamp"])),
      turns: turns
    }
  end

  # pi-research drives pi with a prompt that is a path into its own install
  defp machine?(first),
    do: Enum.any?(@machine_openers, &String.starts_with?(first, &1)) or String.starts_with?(first, Path.expand("~/.pi/"))

  # "test", "q", "config": a session whose every prompt is one bare word was checking the harness
  defp smoke_test?(turns),
    do: Enum.all?(for({:operator, text, _} <- turns, do: text), &(not String.contains?(&1, [" ", "\n"])))

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

  defp prompt(%{"type" => "message", "message" => %{"role" => "user", "content" => content}}) do
    case text_of(content) do
      "" -> nil
      text -> text
    end
  end

  defp prompt(_), do: nil

  defp reply(%{"type" => "assistant", "message" => %{"content" => content}} = e) do
    text = text_of(content)
    if e["isSidechain"] || text == "", do: nil, else: text
  end

  defp reply(%{"type" => "message", "message" => %{"role" => "assistant", "content" => content}}) do
    case text_of(content) do
      "" -> nil
      text -> text
    end
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
  def import_dir(dir, workspace_id), do: dir |> Path.expand() |> Path.join("*/*.jsonl") |> import_glob(workspace_id)

  @doc """
  `import_dir/2` over every transcript a glob (or list of globs) matches, Claude Code's or pi's
  (`Server.Import.PiSessions`).
  """
  def import_glob(glob, workspace_id) do
    projects = Projects.in_workspace(workspace_id)
    fallback = Projects.default(workspace_id)
    paths = glob |> List.wrap() |> Enum.flat_map(&Path.wildcard/1)
    sessions = paths |> Enum.reject(&live?/1) |> Enum.map(&parse/1) |> Enum.reject(&is_nil/1) |> longest_copies()

    imported =
      Enum.count(sessions, fn session ->
        not imported?(session) and
          match?({:ok, _}, insert(session, workspace_id, home_for(session.cwd, projects, fallback)))
      end)

    {:ok, %{imported: imported, skipped: length(paths) - imported}}
  end

  # A transcript written to within the window is a session still running: imported now it would
  # freeze half-way, and the receipt would stop every later run from finishing it.
  defp live?(path) do
    window = Application.get_env(:server, :import_live_window_s, 3600)
    File.stat!(path, time: :posix).mtime > System.os_time(:second) - window
  end

  # A resumed or forked session copies the conversation it came from into a new file, so one
  # opening turn (same text, same time) heads several transcripts; the longest is the conversation.
  defp longest_copies(sessions) do
    sessions
    |> Enum.group_by(fn %{turns: [{:operator, text, at} | _]} -> {text, at} end)
    |> Enum.map(fn {_opening, copies} -> Enum.max_by(copies, &length(&1.turns)) end)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  defp receipt(%{source: :pi, id: id}), do: "↳ imported from pi session #{id}"
  defp receipt(%{id: id}), do: "↳ imported from Claude Code session #{id}"

  defp imported?(session) do
    Repo.exists?(from m in Message, where: m.author == "tlon" and m.body == ^receipt(session))
  end

  # The deepest repo that contains the cwd, so ~/projects/ficciones/modules/x lands on ficciones.
  defp home_for(nil, _projects, fallback), do: {fallback, nil}

  defp home_for(cwd, projects, fallback) do
    projects
    |> Enum.flat_map(fn p ->
      for %{"path" => path} <- p.repos || [], not String.contains?(path, "*"), do: {Path.expand(path), p, path}
    end)
    |> Enum.filter(fn {root, _, _} -> cwd == root or String.starts_with?(cwd, root <> "/") end)
    |> Enum.max_by(fn {root, _, _} -> String.length(root) end, fn -> {nil, fallback, nil} end)
    |> then(fn {_root, project, path} -> {project, path} end)
  end

  defp insert(session, workspace_id, {project, repo}) do
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
          repo: repo,
          created_at: session.started_at
        })

      rows =
        Enum.map([{:tlon, receipt(session), session.started_at} | session.turns], fn {who, body, at} ->
          %{
            thread_id: thread.id,
            author: author(who, operator, session.source),
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

  defp author(:tlon, _operator, _source), do: "tlon"
  defp author(:operator, operator, _source), do: operator
  defp author(:claude, _operator, :pi), do: "pi"
  defp author(:claude, _operator, _source), do: "claude-code"

  defp cap(body) when byte_size(body) <= @body_cap, do: body
  defp cap(body), do: String.slice(body, 0, @body_cap) <> "\n… (cut at import)"
end
