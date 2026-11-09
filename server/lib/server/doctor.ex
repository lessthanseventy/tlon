defmodule Server.Doctor do
  @moduledoc """
  The 2am report. Ask the database itself whether it is sound — the arbiter's own
  answers, not our bookkeeping — and provide the JSONL escape hatch that makes it
  repairable with a text editor.

  The `.git/config.lock` check is honest only on the host (`mise run server:doctor`): inside a seat the
  bind-mounted `/dev/null` always holds that lock, so its report can't be trusted there.
  """
  alias Server.Repo

  @type report :: %{integrity: String.t(), tables: [String.t()], pending: non_neg_integer()}

  @spec report() :: report()
  def report do
    %{integrity: integrity_check(), tables: tables(), pending: length(pending())}
  end

  @doc """
  `ok` when the store answers and schema `public` holds at least one table (a count of its
  `pg_class` relations), else `no tables in schema public`. Postgres has no integrity pragma, so
  this is the honest 2am question: can the store answer, and are its relations there. A store that
  cannot answer raises, and the caller reports that.
  """
  @spec integrity_check() :: String.t()
  def integrity_check do
    case Repo.query!("SELECT count(*) FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace").rows do
      [[n]] when n > 0 -> "ok"
      _ -> "no tables in schema public"
    end
  end

  @doc """
  User tables present — the migration ledger and Oban's own tables excluded.
  """
  @spec tables() :: [String.t()]
  def tables do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        AND table_name <> 'schema_migrations' AND table_name NOT LIKE 'oban\\_%' ESCAPE '\\'
      ORDER BY table_name
      """)

    Enum.map(rows, fn [name] -> name end)
  end

  @doc "Migrations known but not yet applied — a non-empty list means the schema is behind."
  @spec pending() :: [{integer(), String.t()}]
  def pending do
    Repo
    |> Ecto.Migrator.migrations()
    |> Enum.filter(fn {status, _version, _name} -> status == :down end)
    |> Enum.map(fn {_status, version, name} -> {version, name} end)
  end

  @doc """
  The newest crash dump, as one report line: `none`, or its path and age, read against the service's
  start (`started_at`, from `service_started_at/0`). Two places hold them: `erl_crash.dump` at `root`
  (the tlon checkout) and the `*.dump` files `tlon-cli.sh` sends its client nodes to (`dumps_dir`).
  A root dump from before the start means the last restart followed a crash; one written since can't
  be the running service's, so another node here crashed (a mix run at the root). A client node's
  dump is never the service's, before the start or after. With no known start, the dump and its age
  alone.
  """
  @spec crash_dump(Path.t(), DateTime.t() | nil, Path.t()) :: String.t()
  def crash_dump(root \\ Server.Profiles.tlon_root(), started_at \\ service_started_at(), dumps_dir \\ dumps_dir()) do
    candidates =
      [
        {Path.join(root, "erl_crash.dump"), :root}
        | for(p <- Path.wildcard(Path.join(dumps_dir, "*.dump")), do: {p, :client})
      ]

    dumps =
      for {path, from} <- candidates, {:ok, %{mtime: mtime}} <- [File.stat(path, time: :posix)], do: {path, from, mtime}

    case Enum.max_by(dumps, fn {_path, _from, mtime} -> mtime end, fn -> nil end) do
      nil -> "none"
      {path, from, mtime} -> dump_line(path, from, mtime, started_at)
    end
  end

  @doc """
  Where `tlon-cli.sh` sends its client nodes' crash dumps.
  """
  @spec dumps_dir() :: Path.t()
  def dumps_dir do
    state = System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")
    Path.join([state, "tlon", "crash-dumps"])
  end

  @doc """
  When the `tlon` user service last became active, from systemd; nil where there is no systemd,
  no such unit, or it never started.
  """
  @spec service_started_at() :: DateTime.t() | nil
  def service_started_at do
    args = ["--user", "show", "tlon", "-p", "ActiveEnterTimestamp", "--value", "--timestamp=unix"]

    with {"@" <> secs, 0} <- Server.Cmd.run("systemctl", args, stderr_to_stdout: true),
         {n, _} when n > 0 <- Integer.parse(secs) do
      DateTime.from_unix!(n)
    else
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  @git_fetch_urls [
    {~s|url."https://github.com/".insteadOf|, "url.https://github.com/.insteadof", "git@github.com:"},
    {~s|url."git@github.com:".pushInsteadOf|, "url.git@github.com:.pushinsteadof", "git@github.com:"}
  ]

  @doc """
  Whether the checkout at `root` fetches over HTTPS and pushes over SSH, as one report line: `ok`, or
  the `insteadOf` lines missing from its shared `.git/config` and the task that sets them. A sandboxed
  seat cannot read `~/.ssh`, so a fetch over SSH dies there; the repo is public, so HTTPS needs no
  credentials.
  """
  @spec git_fetch_urls(Path.t()) :: String.t()
  def git_fetch_urls(root \\ Server.Profiles.tlon_root()) do
    {config, _} =
      Server.Git.cmd(root, ["config", "--local", "--get-regexp", "^url\\."])

    set = config |> String.split("\n", trim: true) |> MapSet.new()

    case for({name, key, value} <- @git_fetch_urls, "#{key} #{value}" not in set, do: name) do
      [] ->
        "ok"

      missing ->
        "missing #{Enum.join(missing, ", ")} — fetch over SSH is refused in a sandbox; `mise run server:setup` sets them"
    end
  end

  @doc """
  The seat checkouts under `root/.worktrees` and the scratch checkouts under `scratch_dir` whose
  `mise.toml` mise has not trusted, as one report line: `ok`, or their paths and the `mise trust` to run.
  mise ignores an untrusted config silently, so a host `mix` would run on the machine's global pin.
  """
  @spec untrusted_checkouts(Path.t(), Path.t()) :: String.t()
  def untrusted_checkouts(root \\ Server.Profiles.tlon_root(), scratch_dir \\ scratch_dir()) do
    dirs =
      Path.wildcard(Path.join([root, ".worktrees", "*"])) ++
        Path.wildcard(Path.join(scratch_dir, "*")) ++ Path.wildcard(Path.join(scratch_dir, "*/*"))

    untrusted =
      for dir <- dirs,
          File.exists?(Path.join(dir, ".git")),
          File.exists?(Path.join(dir, "mise.toml")),
          {out, _} = Server.Cmd.run("mise", ["trust", "--show", "-C", dir], stderr_to_stdout: true),
          out =~ "#{dir}: untrusted",
          do: dir

    case untrusted do
      [] -> "ok"
      dirs -> "untrusted mise.toml in #{Enum.join(dirs, ", ")} — `mise trust <dir>` each"
    end
  rescue
    ErlangError -> "ok"
  end

  @doc """
  What the seat checkouts under `root/.worktrees` cost on disk, as one report line. Checkouts copy
  `deps` and `_build` with `cp --reflink`, so plain `du` counts every shared block once per checkout
  and alarms; on btrfs the line gives the exclusive bytes (`btrfs filesystem du`), elsewhere `du`.
  `cmd` runs the commands and is injectable so the parse is testable.
  """
  @spec worktree_size(Path.t(), (String.t(), [String.t()], keyword() -> {String.t(), integer()})) :: String.t()
  def worktree_size(root \\ Server.Profiles.tlon_root(), cmd \\ &Server.Cmd.run/3) do
    dir = Path.join(root, ".worktrees")

    if File.dir?(dir) do
      case exclusive_bytes(cmd, dir) do
        {:ok, bytes} -> "#{format_bytes(bytes)} exclusive (btrfs: blocks shared between checkouts counted once)"
        :error -> du_line(cmd, dir)
      end
    else
      "none"
    end
  end

  @stale_lock_seconds 300

  @doc """
  The checkout's `.git/config.lock` at `root`, as one report line: `ok`, or `stale` with the `rm` for
  the operator. A lock is stale when it is older than a few minutes and no `bwrap` is running; a live
  sandbox's lock is also 0-byte, so age plus no sandbox is the only tell. `bwrap_running?` is injectable
  so the check is deterministic in tests.
  """
  @spec config_lock(Path.t(), (-> boolean())) :: String.t()
  def config_lock(root \\ Server.Profiles.tlon_root(), bwrap_running? \\ &bwrap_running?/0) do
    path = Path.join([root, ".git", "config.lock"])

    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} ->
        if System.os_time(:second) - mtime > @stale_lock_seconds and not bwrap_running?.() do
          "stale #{path} — no sandbox is running; `rm #{path}`"
        else
          "ok"
        end

      {:error, _} ->
        "ok"
    end
  end

  defp bwrap_running? do
    match?({_, code} when code in [0, 127], Server.Cmd.run("pgrep", ["-x", "bwrap"], stderr_to_stdout: true))
  rescue
    ErlangError -> true
  end

  @doc """
  Export every table as JSONL into `dir` (created if missing), one `<table>.jsonl` per table —
  `mix server.doctor --export <dir>`. Returns the paths written, in table order; an empty table
  writes an empty file, so a missing file always means a missing table.
  """
  @spec export(Path.t()) :: [Path.t()]
  def export(dir) do
    File.mkdir_p!(dir)

    for table <- tables() do
      path = Path.join(dir, "#{table}.jsonl")
      File.write!(path, jsonl_file(table_to_jsonl(table)))
      path
    end
  end

  defp jsonl_file(""), do: ""
  defp jsonl_file(lines), do: lines <> "\n"

  @doc """
  Export one table as JSONL — the escape hatch. The table name cannot be a bound
  parameter, so it is validated against the live schema before it is interpolated:
  an unknown name is refused, not run.
  """
  @spec table_to_jsonl(String.t()) :: String.t()
  def table_to_jsonl(table) do
    if table not in tables(), do: raise(ArgumentError, "no such table: #{table}")

    %{rows: rows, columns: columns} = Repo.query!(~s|SELECT * FROM "#{table}"|)

    Enum.map_join(rows, "\n", fn row ->
      columns |> Enum.zip(row) |> Map.new() |> JSON.encode!()
    end)
  end

  defp scratch_dir do
    System.get_env("TLON_SCRATCH_DIR") ||
      Path.join(System.get_env("XDG_CACHE_HOME") || Path.expand("~/.cache"), "tlon-scratch")
  end

  defp dump_line(path, from, mtime, started_at) do
    age = "#{path}, #{div(System.os_time(:second) - mtime, 3600)}h old"
    since_start = started_at && mtime >= DateTime.to_unix(started_at)

    case {from, since_start} do
      {_, nil} ->
        "#{age} — service start unknown"

      {:client, true} ->
        "#{age} — a tlon-cli client node's, written since the service started at #{started_at}: not the service"

      {:client, false} ->
        "#{age} — a tlon-cli client node's, before the service started at #{started_at}: not the service"

      {:root, true} ->
        "#{age} — written since the service started at #{started_at}: not the service (it's up), another node here crashed"

      {:root, false} ->
        "#{age} — before the service started at #{started_at}: the last restart followed a crash"
    end
  end

  defp exclusive_bytes(cmd, dir) do
    with {out, 0} <- cmd.("btrfs", ["filesystem", "du", "-s", "--raw", dir], stderr_to_stdout: true),
         [_header, row | _] <- String.split(out, "\n", trim: true),
         [_total, exclusive | _] <- String.split(row),
         {bytes, ""} <- Integer.parse(exclusive) do
      {:ok, bytes}
    else
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end

  defp du_line(cmd, dir) do
    with {out, 0} <- cmd.("du", ["-sk", dir], stderr_to_stdout: true),
         [kb | _] <- String.split(out),
         {kb, ""} <- Integer.parse(kb) do
      "#{format_bytes(kb * 1024)} by du (checkouts' reflinked blocks counted each time, so an overstatement)"
    else
      _ -> "unknown"
    end
  rescue
    ErlangError -> "unknown"
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824, do: "#{Float.round(bytes / 1_073_741_824, 1)} GiB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"
end
