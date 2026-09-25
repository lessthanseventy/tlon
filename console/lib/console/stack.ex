defmodule Console.Stack do
  @moduledoc """
  The machine/stack read models for the **Tlön** space (§the meta lens): what's changed in the
  env (recent `ficciones` commits with relative time and author — the stack's own changelog),
  what's installed (tool versions), and what's the system state (branch, dirty status, nix
  generation, disk/memory). Best-effort and honest: a missing `git` or tool yields an empty/`"?"`
  value, never a crash. Tool versions are cached in `:persistent_term` (they don't change
  mid-session); commits and system state are read fresh on each Cockpit tick.
  """
  @default_tools [
    {"pi", ["--version"]},
    {"claude", ["--version"]},
    {"nix", ["--version"]},
    {"mise", ["--version"]},
    {"tmux", ["-V"]}
  ]

  @doc """
  Recent `ficciones` commits as `[%{hash, subject, author, agent?, relative, date}]`, newest
  first (best-effort, fresh). `date` is a short absolute stamp ("Nov 24 14:32", from git).

  `author` prefers the commit's `Co-Authored-By:` trailer over `%an` (the git identity) — per
  the repo's commit convention (root `AGENTS.md`), an agent-authored commit is still pushed
  under the human's git identity, so `%an` alone would credit every dogfood commit to the human
  who happened to be at the keyboard instead of the model that actually wrote it. `agent?` is
  true when a trailer was found, so the panel can style attribution differently for "a model
  wrote this" vs "a human wrote this".

  `relative` ("5 minutes ago") is computed here, NOT by git's own `%ar` — git buckets each
  commit against the exact second it's asked, so commits with different sub-minute offsets
  flip to the next bucket at different, apparently-random wall-clock moments as the panel
  re-renders. `relative_time/2` instead rounds "now" down to the current minute first, so
  every commit's bucket is computed against the same anchor and they all advance together,
  exactly on the minute.
  """
  def commits(dir \\ ".", n \\ 8) do
    case cmd("git", ["-C", dir, "log", "--format=#{format()}", date_format(), "-n", Integer.to_string(n)]) do
      {:ok, out} ->
        now = System.os_time(:second)
        out |> String.split("\n", trim: true) |> Enum.map(&parse_commit(&1, now))

      :error ->
        []
    end
  end

  @doc """
  A commit's diff as classified lines — `[%{text, kind}]` where `kind` is `:file` (a `diff --git`
  header), `:hunk` (`@@ … @@`), `:add`/`:del` (a `+`/`-` line), `:meta` (the commit header, `index`,
  `+++`/`---` file markers), or `:context`. `git show <hash>` for the Commits pane's `Enter` detail
  in MAIN; the renderer colors off `kind` and stays dumb. Best-effort: `[]` outside a repo, on a
  bad hash, or on failure — never a crash. `hash` is a discrete argv (no shell), so a listed short
  hash can't inject.
  """
  def show(hash, dir \\ ".")
  def show(nil, _dir), do: []
  def show("", _dir), do: []

  def show(hash, dir) do
    case cmd("git", ["-C", dir, "show", "--no-color", hash]) do
      {:ok, out} -> out |> String.split("\n") |> Enum.map(&classify_diff_line/1)
      :error -> []
    end
  end

  # Order matters: the "+++"/"---" file markers must be caught as :meta BEFORE the bare +/- add/del
  # tests, and "diff --git" before the "-" test (it starts with "d", but be explicit).
  defp classify_diff_line("diff --git" <> _ = l), do: %{text: l, kind: :file}
  defp classify_diff_line("@@" <> _ = l), do: %{text: l, kind: :hunk}
  defp classify_diff_line("+++" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("---" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("index " <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("new file" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("deleted file" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("rename " <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("similarity " <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("commit " <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("Author:" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("Date:" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("Merge:" <> _ = l), do: %{text: l, kind: :meta}
  defp classify_diff_line("+" <> _ = l), do: %{text: l, kind: :add}
  defp classify_diff_line("-" <> _ = l), do: %{text: l, kind: :del}
  defp classify_diff_line(l), do: %{text: l, kind: :context}

  @doc """
  "5 minutes ago"-style relative time, rounded against `now` truncated to the current minute
  (see `commits/2` doc) so a batch of commits all advance a bucket in lockstep. `nil` timestamp
  (unparseable `%at`) yields "?".
  """
  def relative_time(nil, _now), do: "?"

  def relative_time(timestamp, now) do
    anchor = div(now, 60) * 60
    diff = max(anchor - timestamp, 0)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> plural(div(diff, 60), "minute")
      diff < 86_400 -> plural(div(diff, 3_600), "hour")
      diff < 604_800 -> plural(div(diff, 86_400), "day")
      true -> plural(div(diff, 604_800), "week")
    end
  end

  defp plural(1, unit), do: "1 #{unit} ago"
  defp plural(n, unit), do: "#{n} #{unit}s ago"

  @doc """
  Recently touched files, most-recent first, deduped across the last `commits` commits, capped
  to `n` (best-effort, `[]` outside a git repo or on failure). Reads `git log --name-only`
  across a window rather than just the latest commit so a quiet stretch still shows something —
  the point is "what's been moving lately", not strictly "what changed last commit".
  """
  def recent_files(dir \\ ".", commits \\ 20, n \\ 6) do
    case cmd("git", ["-C", dir, "log", "--name-only", "--format=", "-n", Integer.to_string(commits)]) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> Enum.uniq() |> Enum.take(n)
      :error -> []
    end
  end

  @doc "Current branch name, or nil if not in a git repo."
  def branch(dir \\ ".") do
    case cmd("git", ["-C", dir, "branch", "--show-current"]) do
      {:ok, out} -> out |> String.trim() |> then(&if &1 != "", do: &1)
      :error -> nil
    end
  end

  @doc "Whether the working tree has uncommitted changes (best-effort)."
  def dirty?(dir \\ ".") do
    case cmd("git", ["-C", dir, "status", "--porcelain"]) do
      {:ok, out} -> String.trim(out) != ""
      :error -> false
    end
  end

  @doc ~S"""
  The running build's identity for HEALTH — `git describe --tags --always --dirty`: a release tag
  when HEAD is exactly one, else `<tag>-<n>-g<sha>` when ahead of the last tag, else the bare short
  SHA; a `-dirty` suffix marks an uncommitted tree. "?" outside a git repo. Cached after the first
  probe (like `tools/0`) — the running build is fixed for the process lifetime, so it must NOT
  re-read per health tick (which would fork git every second and could drift mid-session).
  """
  def release do
    case :persistent_term.get({__MODULE__, :release}, nil) do
      nil ->
        probed = probe_release()
        :persistent_term.put({__MODULE__, :release}, probed)
        probed

      cached ->
        cached
    end
  end

  defp probe_release do
    case cmd("git", ["-C", ".", "describe", "--tags", "--always", "--dirty"]) do
      {:ok, out} -> out |> String.trim() |> then(&if(&1 == "", do: "?", else: &1))
      :error -> "?"
    end
  end

  @doc "Installed tool versions as `[%{name, version}]`, cached after the first probe."
  def tools do
    case :persistent_term.get({__MODULE__, :tools}, nil) do
      nil ->
        probed = Enum.map(@default_tools, fn {name, args} -> %{name: name, version: version(name, args)} end)
        :persistent_term.put({__MODULE__, :tools}, probed)
        probed

      cached ->
        cached
    end
  end

  @doc """
  One nix-env call for both readings: `{current_gen, behind_count}`, or `{nil, nil}` on failure.
  nix-env --list-generations prints one gen per line; the current gen is marked "(current)".
  "Behind" = how many generations have a higher number than the current one (rollback gap).
  Tries home-manager first (common on non-NixOS), then the system profile. This is the single
  most expensive probe in the health battery — callers should destructure this rather than call
  `nix_behind/0` alongside it (each runs the full sweep again).
  """
  def nix_status do
    Enum.reduce_while(nix_profile_paths(), {nil, nil}, fn path, _acc -> nix_gens_at(path) end)
  end

  defp nix_gens_at(path) do
    case cmd("nix-env", ["--list-generations", "--profile", path]) do
      {:ok, out} ->
        result = parse_nix_gens(out)
        if elem(result, 0) == nil, do: {:cont, {nil, nil}}, else: {:halt, result}

      :error ->
        {:cont, {nil, nil}}
    end
  end

  # Profile paths to try, in order: home-manager (non-NixOS), then the system default.
  defp nix_profile_paths do
    home = System.user_home!()
    [Path.join(home, ".local/state/nix/profiles/home-manager"), "/nix/var/nix/profiles/default"]
  end

  defp parse_nix_gens(out) do
    lines = String.split(out, "\n", trim: true)

    current_gen =
      Enum.find_value(lines, fn line ->
        if String.contains?(line, "(current)"), do: parse_nix_gen(line)
      end)

    behind =
      if current_gen do
        Enum.count(lines, fn line ->
          gen = parse_nix_gen(line)
          gen != nil and gen > current_gen
        end)
      else
        0
      end

    {current_gen, behind}
  end

  @doc "How many generations behind the current one is. 0 means current, nil if unknown."
  def nix_behind, do: elem(nix_status(), 1)

  @doc "Disk usage percentage for the root filesystem (best-effort)."
  def disk_pct do
    # GNU coreutils uses `pcent` (percent), not `pct`. Fall back to parsing `df -h`
    # on systems where --output isn't available.
    case cmd("df", ["--output=pcent", "/"]) do
      {:ok, out} ->
        out |> String.split("\n", trim: true) |> List.last() |> String.trim() |> parse_pct()

      :error ->
        disk_pct_df_h()
    end
  end

  defp disk_pct_df_h do
    case cmd("df", ["-h", "/"]) do
      {:ok, out} ->
        out
        |> String.split("\n", trim: true)
        |> List.last()
        |> String.split()
        |> Enum.at(-2, "")
        |> String.replace("%", "")
        |> parse_pct()

      :error ->
        nil
    end
  end

  @doc "Memory usage percentage (best-effort, reads from /proc/meminfo on Linux)."
  def mem_pct do
    with {:ok, content} <- File.read("/proc/meminfo"),
         {total, _} <- parse_mem_line(content, "MemTotal:"),
         {available, _} <- parse_mem_line(content, "MemAvailable:"),
         true <- total > 0 do
      round((total - available) / total * 100)
    else
      _ -> nil
    end
  end

  @doc "System 1-minute load average, or nil. Best-effort, reads /proc/loadavg on Linux."
  def load_avg do
    with {:ok, content} <- File.read("/proc/loadavg"),
         [one_min | _] <- String.split(content),
         {f, _} <- Float.parse(one_min) do
      Float.round(f, 2)
    else
      _ -> nil
    end
  end

  @doc "Commits ahead/behind the tracking branch, or {nil, nil}. Best-effort."
  def ahead_behind(dir \\ ".") do
    case cmd("git", ["-C", dir, "rev-list", "--left-right", "--count", "@{upstream}...HEAD"]) do
      {:ok, out} ->
        case String.split(String.trim(out), "\t", parts: 2) do
          [behind, ahead] ->
            {to_integer(ahead), to_integer(behind)}

          _ ->
            {nil, nil}
        end

      :error ->
        {nil, nil}
    end
  end

  @doc """
  Git status summary: %{staged, unstaged, untracked} counts from `git status --porcelain`.
  Nil if not in a git repo. Staged = files in the index (X column not blank/?);
  unstaged = modified in the worktree (Y column not blank/?); untracked = `??` lines.
  """
  def status_summary(dir \\ ".") do
    case cmd("git", ["-C", dir, "status", "--porcelain"]) do
      {:ok, out} ->
        lines = String.split(out, "\n", trim: true)

        staged =
          Enum.count(lines, fn l ->
            String.length(l) >= 1 and String.at(l, 0) not in [" ", "?"]
          end)

        unstaged =
          Enum.count(lines, fn l ->
            String.length(l) >= 2 and String.at(l, 1) not in [" ", "?"]
          end)

        untracked = Enum.count(lines, &String.starts_with?(&1, "??"))
        %{staged: staged, unstaged: unstaged, untracked: untracked}

      :error ->
        nil
    end
  end

  # 150ms, down from 500: loopback either connects or refuses in microseconds; the timeout only
  # matters when the port is black-holed, where it bounds how long the cockpit's probe blocks.
  @funes_probe_timeout_ms 150

  @doc "Whether the server always-up service is reachable on :4040 (the systemd service, NOT console's own 4041 workspace)."
  def funes_up? do
    case :gen_tcp.connect(~c"127.0.0.1", 4040, [], @funes_probe_timeout_ms) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Whether the active Workspace's tmux session exists on its own private server (`Console.Tmux`).
  """
  def tlon_up? do
    case Console.Space.first_workspace() do
      # No workspace at all (server down; the fallback Workspace is gone, reshape slice A) — nothing is up.
      nil ->
        false

      %{id: id} ->
        case cmd("tmux", Console.Tmux.argv(id, ["has-session", "-t", Console.Tmux.session(id)])) do
          {:ok, _} -> true
          :error -> false
        end
    end
  end

  # -- format: hash<tab>author_date_unix<tab>short_date<tab>git_author<tab>subject<tab>co_authors
  # The trailer placeholder needs git >= 2.31; older git just prints it literally as the last
  # field, which co_author/1 below then fails to split on "<" and falls back to the git author.
  defp format, do: "%h%x09%at%x09%ad%x09%an%x09%s%x09%(trailers:key=Co-Authored-By,valueonly,separator=%x2C)"
  defp date_format, do: "--date=format:%b %d %H:%M"

  defp parse_commit(line, now) do
    case String.split(line, "\t", parts: 6) do
      [hash, ts, date, git_author, subject, trailer] ->
        timestamp = to_integer(ts)

        {author, agent?} =
          case co_authors(trailer) do
            nil -> {git_author, false}
            names -> {names, true}
          end

        %{
          hash: hash,
          relative: relative_time(timestamp, now),
          date: date,
          author: author,
          agent?: agent?,
          subject: subject
        }

      [hash, subject] ->
        %{hash: hash, relative: "?", date: "?", author: "?", agent?: false, subject: subject}

      [hash] ->
        %{hash: hash, relative: "?", date: "?", author: "?", agent?: false, subject: ""}
    end
  end

  # "Model Name <email>, Other Model <email>" -> "Model Name + Other Model", or nil if there's
  # no trailer (a plain human commit). Trailing parentheticals like "(1M context)" are stripped
  # from each name — panel real estate, not identity.
  defp co_authors(""), do: nil

  defp co_authors(trailer) do
    trailer
    |> String.split(",")
    |> Enum.map(fn entry ->
      entry
      |> String.trim()
      |> String.split("<", parts: 2)
      |> List.first()
      |> String.trim()
      |> String.replace(~r/\s*\([^)]*\)\s*$/, "")
    end)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      names -> Enum.join(names, " + ")
    end
  end

  defp parse_nix_gen(nil), do: nil
  defp parse_nix_gen(line), do: line |> String.split() |> List.first() |> to_integer()

  defp to_integer(nil), do: nil

  defp to_integer(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_pct(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_mem_line(content, prefix) do
    case Regex.run(~r/#{prefix}\s+(\d+)/, content) do
      [_, num] -> {String.to_integer(num), content}
      _ -> nil
    end
  end

  # First non-empty line of the tool's version output, or "?" if it isn't installed / errored.
  defp version(name, args) do
    case cmd(name, args) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> List.first() |> to_string() |> String.trim()
      :error -> "?"
    end
  end

  defp cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end
end
