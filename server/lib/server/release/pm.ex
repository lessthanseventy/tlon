defmodule Server.Release.PM do
  @moduledoc """
  The PM's release desk (pm-and-release design §4, §6): what waits on main, a proposed cut, the
  gate it reaches the operator through, the cut, and its changelog. The `pm` archetype's tools
  (`release_status`, `check_candidate`, `propose_release`) call it.

  **The grade is the max, not a sum.** A proposal is graded commit by commit with
  `Server.Workline.Grade.assess/2`, and fits the standing approval (`auto_land_risk`) only when every
  commit would on its own: the worst over its commits, axis by axis. A sum would push any release of
  a few changes past a per-axis threshold no single change came near. Grading stops at the first
  commit that doesn't fit, and that commit is what the gate names; a grader limit (a migration, a
  dependency, the gate, the law, a deleted test, a commit too big to grade) always holds it.

  Fits: the PM cuts it and says so. Doesn't: ONE gate on the workspace's root thread — a `prompt`
  no pane holds (`payload["release"]`), on the operator's list as a dialog and answered like one
  (`Server.Attention.respond/3`): approve queues the cut, not yet leaves it. Nothing is cut unless
  `Server.Release.Candidate.releasable?/2` holds at that moment.

  A cut runs `scripts/release.sh cut <sha> --no-restart` in the tlon checkout, records the changelog
  as event `release:<sha>` (`check_passed`), posts it to the root thread, and only then asks for the
  quiet restart, so the changelog is never lost to the restart it causes. The changelog's worklines
  are found by time — merged after the old release's commit and up to the new one's — because a
  landed commit's id differs from its branch's.

  Opts stand in for the world in a test: `root:` (the tlon checkout; else the `:release_root` app
  env, else `Server.Profiles.tlon_root/0`), `script:`, `busy:` (for `Candidate.check/2`),
  `restart:` (`fn why -> _ end`), `auto_land_risk:`, `run:` (fires a schedule; else
  `Server.Schedules.run_now/1`).
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Event
  alias Server.Message
  alias Server.Release.Candidate
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Grade

  @options [%{"key" => "a", "label" => "approve"}, %{"key" => "n", "label" => "not yet"}]

  # the checks a candidate needs run on it: {check name its run records, schedule title, command, cron}
  @checks [
    {"gate", "nightly gate on main", "mise run check:main", "0 3 * * *"},
    {"smoke", "nightly smoke on main", "mise run release:smoke", "30 3 * * *"}
  ]
  @running_for 3600

  @doc "What runs (`live`), origin/main, the commits waiting (oldest first), and main's checks as lines."
  def status(opts \\ []) do
    root = root(opts)
    fetch(root)

    with {:ok, live} <- live(root),
         {:ok, main} <- rev(root, "origin/main") do
      {:ok,
       %{live: live, main: main, waiting: commits(root, live, main), checks: Candidate.lines(main, check_opts(opts))}}
    end
  end

  @doc """
  Run the gate and the smoke on main's tip now rather than waiting for the night: each fires its
  schedule in `workspace_id` (a standing nightly one made if it has none), unless it already passed
  on the tip or is running. Each run records the commit it checked, so `status/1` reads the verdict
  once it finishes. `{:ok, [%{check, state: "started" | "passed" | "running", why}]}`.
  """
  def check(workspace_id, opts \\ []) do
    root = root(opts)
    fetch(root)
    fire = opts[:run] || (&Server.Schedules.run_now/1)

    with {:ok, main} <- rev(root, "origin/main") do
      results = Candidate.check(main, check_opts(opts))

      {:ok,
       for {name, title, cmd, cron} <- @checks do
         s = schedule(workspace_id, root, title, cmd, cron)

         cond do
           Enum.find(results, &(to_string(&1.check) == name)).ok ->
             %{check: name, state: "passed", why: "#{cmd} already passed on #{short(main)}"}

           running?(s) ->
             %{check: name, state: "running", why: "#{cmd} is running now; read release_status when it finishes"}

           true ->
             fire.(s)
             %{check: name, state: "started", why: "#{cmd} started on origin/main (#{short(main)})"}
         end
       end}
    end
  end

  defp schedule(workspace_id, root, title, cmd, cron) do
    case Repo.one(
           from s in Server.Schedule,
             where: s.workspace_id == ^workspace_id and s.kind == "script" and s.body == ^cmd,
             order_by: [asc: s.id],
             limit: 1
         ) do
      nil ->
        {:ok, s} =
          Server.Schedules.create(%{
            workspace_id: workspace_id,
            kind: "script",
            title: title,
            body: cmd,
            cron: cron,
            standing: true,
            dir: root
          })

        s

      s ->
        s
    end
  end

  # a run left `running` past the script timeout died with its node; it holds nothing
  defp running?(s) do
    since = DateTime.add(DateTime.utc_now(), -@running_for, :second)

    Repo.exists?(
      from r in Server.ScheduleRun,
        where: r.schedule_id == ^s.id and r.status == "running" and r.started_at > ^since
    )
  end

  @doc """
  Propose releasing `sha` (default origin/main) from `workspace_id`: refused unless it is on main,
  ahead of live, and releasable; else queued to be graded (`Server.Jobs.Release`), whose outcome —
  the cut, or the gate — posts to the root thread. `notes` is the PM's changelog, in the operator's
  words. `{:ok, %{sha, changes}}` | `{:error, why}`.
  """
  def propose(workspace_id, sha, notes, opts \\ []) do
    root = root(opts)
    fetch(root)

    with {:ok, target} <- target(root, sha),
         {:ok, live} <- live(root),
         {:ok, commits} <- ahead(root, live, target),
         :ok <- releasable(target, opts),
         {:ok, _job} <- queue("decide", workspace_id, target, notes) do
      {:ok, %{sha: target, changes: length(commits)}}
    end
  end

  @doc """
  Grade the proposal and act on it: every commit fits `auto_land_risk` → `cut/4` (`{:ok,
  changelog}`); else the gate (`{:gate, message}`). `{:error, why}` — said on the root thread — when
  it is no longer releasable or ahead of live.
  """
  def decide(workspace_id, sha, notes, opts \\ []) do
    root = root(opts)
    max = Keyword.get_lazy(opts, :auto_land_risk, fn -> Server.OperatorConfig.setting("auto_land_risk") end)

    with {:ok, live} <- live(root),
         {:ok, commits} <- ahead(root, live, sha),
         :ok <- releasable(sha, opts) do
      case verdict(root, commits, max) do
        :fits ->
          notice(
            workspace_id,
            "⚖ release #{short(sha)}: all #{length(commits)} changes fit your standing approval (none over #{max}) — cutting it"
          )

          cut(workspace_id, sha, notes, opts)

        {:hold, why} ->
          {:gate, gate(workspace_id, sha, live, commits, why, notes, opts)}
      end
    else
      {:error, why} = error ->
        notice(workspace_id, "release #{short(sha)} not proposed: #{why}")
        error
    end
  end

  @doc """
  Cut `sha`: refused unless it is still ahead of live and releasable; else the release script moves
  the pointer and builds, the changelog is recorded and posted, and the restart asked for.
  `{:ok, changelog}` | `{:error, why}`, either way said on the root thread.
  """
  def cut(workspace_id, sha, notes, opts \\ []) do
    root = root(opts)
    script = opts[:script] || Path.join(root, "scripts/release.sh")
    restart = opts[:restart] || fn why -> Server.Rollout.restart(why: why) end

    with {:ok, live} <- live(root),
         {:ok, commits} <- ahead(root, live, sha),
         :ok <- releasable(sha, opts),
         {:ok, _out} <- run(script, root, sha) do
      changelog = changelog(root, live, sha, commits, notes)

      {:ok, _} =
        Server.Dossier.record_event(%{
          thread_id: root_thread_id(workspace_id),
          kind: "check_passed",
          correlation: "release:#{sha}",
          detail: %{"cmd" => "release cut", "exit" => 0, "from" => live, "to" => sha, "changelog" => changelog}
        })

      notice(workspace_id, changelog)
      restart.("release #{short(sha)}")
      {:ok, changelog}
    else
      {:error, why} = error ->
        notice(workspace_id, "release #{short(sha)} not cut: #{why}")
        error
    end
  end

  @doc """
  Say on the root thread that the service runs a new release, once per release: the release
  pointer (`refs/heads/live` — a cut moves it only after building it, so a boot runs what it
  names) against the newest one said. The notice reads `release <sha> is live — N changes`
  (`— back from <sha>` on a rollback, nothing more on the first), payload `%{"live" => sha}`. No
  pointer or no root thread says nothing. `:ok`. `opts`: `root:`.
  """
  def note_live(opts \\ []) do
    root = root(opts)

    said =
      Repo.one(
        from m in Message,
          where: m.kind == "notice" and fragment("? \\? 'live'", m.payload),
          order_by: [desc: m.id],
          limit: 1
      )

    prev = said && said.payload["live"]

    with {:ok, sha} when sha != prev <- live(root),
         %Thread{id: tid} <- Channel.machine_thread() do
      body = "release #{short(sha)} is live" <> since_last(root, prev, sha)
      _ = Channel.post(%{thread_id: tid, author: "tlon", kind: "notice", body: body, payload: %{"live" => sha}})
    end

    :ok
  end

  defp since_last(_root, nil, _sha), do: ""

  defp since_last(root, prev, sha) do
    case git(root, ["merge-base", "--is-ancestor", prev, sha]) do
      {_, 0} -> " — " <> changes(length(commits(root, prev, sha)))
      _ -> " — back from #{short(prev)}"
    end
  end

  defp changes(1), do: "1 change"
  defp changes(n), do: "#{n} changes"

  @doc "The live-release notices (`note_live/1`) posted at or after `since`, newest first."
  def live_since(%DateTime{} = since) do
    Repo.all(
      from m in Message,
        where: m.kind == "notice" and m.created_at >= ^since and fragment("? \\? 'live'", m.payload),
        order_by: [desc: m.id]
    )
  end

  @doc """
  The operator answered a release gate (`Server.Attention.respond/3` has resolved it): `"a"`
  queues the cut, `"n"` holds it.
  """
  def answered(%Message{payload: %{"release" => sha} = p}, key) do
    ws = p["workspace_id"]

    case key do
      "a" ->
        with {:error, why} <- queue("cut", ws, sha, p["notes"]),
             do: notice(ws, "release #{short(sha)} approved, but not queued: #{why}")

      _ ->
        notice(ws, "release #{short(sha)}: not yet — held")
    end

    :ok
  end

  # each commit graded on its own; the first that doesn't fit holds the release
  defp verdict(_root, _commits, nil),
    do: {:hold, "no standing approval is set (auto_land_risk), so every release is yours"}

  defp verdict(root, commits, max) do
    Enum.reduce_while(commits, :fits, fn %{sha: sha, subject: subject}, :fits ->
      case fits(root, sha, max) do
        :ok -> {:cont, :fits}
        {:hold, why} -> {:halt, {:hold, "#{short(sha)} #{subject}: #{why}"}}
      end
    end)
  end

  defp fits(root, sha, max) do
    case Grade.assess(change(root, sha), fn -> %{spec: message(root, sha), plan: nil} end) do
      {:ok, grade} -> if Grade.allows?(grade, max), do: :ok, else: {:hold, Grade.line(grade)}
      {:error, why} -> {:hold, "the grader could not grade it (#{why})"}
    end
  end

  defp gate(workspace_id, sha, live, commits, why, notes, opts) do
    thread_id = root_thread_id(workspace_id)

    for m <- open_gates(thread_id), do: Server.Attention.resolve(m, "superseded")

    summary = "release #{short(sha)}: #{length(commits)} changes — #{why}"

    body =
      Enum.join(
        [
          "⚑ #{summary}",
          "from #{short(live)}; checks on it:" | Enum.map(Candidate.lines(sha, check_opts(opts)), &"  #{&1}")
        ] ++
          if(notes in [nil, ""], do: [], else: ["", notes]) ++
          ["", "changes:" | Enum.map(commits, &"- #{short(&1.sha)} #{&1.subject}")] ++
          ["", Enum.map_join(@options, " · ", &"(#{&1["key"]}) #{&1["label"]}")],
        "\n"
      )

    payload = %{
      "release" => sha,
      "from" => live,
      "notes" => notes,
      "summary" => summary,
      "options" => @options,
      "workspace_id" => workspace_id
    }

    # delivered at birth: the operator's to answer, never typed into a pane
    %{thread_id: thread_id, author: "tlon", body: body, kind: "prompt", payload: payload}
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.insert!()
    |> tap(&Server.Bus.broadcast({:message_posted, &1}))
  end

  defp open_gates(thread_id) do
    Repo.all(
      from m in Message,
        where:
          m.thread_id == ^thread_id and m.kind == "prompt" and is_nil(m.resolved_at) and
            fragment("? ->> 'release' IS NOT NULL", m.payload)
    )
  end

  defp changelog(root, live, sha, commits, notes) do
    worklines =
      for {id, title} <- merged_between(commit_time(root, live), commit_time(root, sha)), do: "- ##{id} #{title}"

    Enum.join(
      ["🚀 shipped to you — release #{short(sha)} (was #{short(live)})"] ++
        if(notes in [nil, ""], do: [], else: [notes]) ++
        if(worklines == [], do: [], else: ["", "worklines:" | worklines]) ++
        ["", "commits (#{length(commits)}):" | Enum.map(commits, &"- #{short(&1.sha)} #{&1.subject}")],
      "\n"
    )
  end

  defp merged_between(from, to) do
    Repo.all(
      from e in Event,
        join: t in Thread,
        on: t.id == e.thread_id,
        where:
          e.kind == "stage_advanced" and fragment("(?::jsonb ->> 'to') = 'merged'", e.detail) and
            e.created_at > ^from and e.created_at <= ^to,
        order_by: [asc: t.id],
        distinct: true,
        select: {t.id, t.title}
    )
  end

  defp queue(action, workspace_id, sha, notes) do
    case Server.Jobs.enqueue(
           Server.Jobs.Release.new(%{action: action, workspace_id: workspace_id, sha: sha, notes: notes})
         ) do
      {:ok, job} -> {:ok, job}
      {:error, :no_oban} -> {:error, "no job queue on this node — the service runs releases"}
      {:error, why} -> {:error, inspect(why)}
    end
  end

  defp releasable(sha, opts) do
    if Candidate.releasable?(sha, check_opts(opts)),
      do: :ok,
      else: {:error, "#{short(sha)} is not releasable: " <> Enum.join(Candidate.lines(sha, check_opts(opts)), "; ")}
  end

  defp check_opts(opts), do: Keyword.take(opts, [:busy])

  defp run(script, root, sha) do
    case System.cmd("bash", [script, "cut", sha, "--no-restart"], cd: root, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, out}

      {out, code} ->
        {:error,
         "the release script failed (exit #{code}): #{out |> String.split("\n", trim: true) |> Enum.take(-5) |> Enum.join(" / ")}"}
    end
  end

  defp notice(workspace_id, body),
    do: Channel.post(%{thread_id: root_thread_id(workspace_id), author: "tlon", body: body, kind: "notice"})

  defp root_thread_id(workspace_id) do
    case Channel.machine_thread(workspace_id) do
      %Thread{id: id} -> id
      nil -> raise "workspace #{workspace_id} has no root thread"
    end
  end

  defp root(opts), do: opts[:root] || Application.get_env(:server, :release_root) || Server.Profiles.tlon_root()

  defp fetch(root), do: git(root, ["fetch", "-q", "origin"])

  defp live(root) do
    case rev(root, "refs/heads/live") do
      {:ok, sha} -> {:ok, sha}
      {:error, _} -> {:error, "no release cut yet — the first is the operator's (mise run release:cut)"}
    end
  end

  defp target(root, sha) do
    with {:ok, target} <- rev(root, "#{sha || "origin/main"}^{commit}") do
      case git(root, ["merge-base", "--is-ancestor", target, "origin/main"]) do
        {_, 0} -> {:ok, target}
        _ -> {:error, "#{short(target)} is not on origin/main — only merged work ships"}
      end
    end
  end

  defp ahead(_root, sha, sha), do: {:error, "nothing waits: live is already #{short(sha)}"}

  defp ahead(root, live, target) do
    case git(root, ["merge-base", "--is-ancestor", live, target]) do
      {_, 0} ->
        {:ok, commits(root, live, target)}

      _ ->
        {:error,
         "#{short(target)} is behind or beside live #{short(live)} — a rollback is the operator's (release:cut -- <sha> --rollback)"}
    end
  end

  defp commits(root, from, to) do
    {out, 0} = git(root, ["log", "--reverse", "--format=%H%x09%s", "#{from}..#{to}"])

    for line <- String.split(out, "\n", trim: true),
        [sha, subject] = String.split(line, "\t", parts: 2),
        do: %{sha: sha, subject: subject}
  end

  # one commit as Grade reads a change: `%{paths, deleted, lines, diff, files}`
  defp change(root, sha) do
    show = fn args -> elem(git(root, ["show", "--format=" | args] ++ [sha]), 0) end
    paths = String.split(show.(["--name-only"]), "\n", trim: true)
    deleted = String.split(show.(["--name-only", "--diff-filter=D"]), "\n", trim: true)

    lines =
      for line <- String.split(show.(["--numstat"]), "\n", trim: true),
          [a, d | _] = String.split(line, "\t"),
          reduce: 0 do
        acc -> acc + count(a) + count(d)
      end

    files =
      for path <- paths -- deleted,
          {text, 0} <- [git(root, ["show", "#{sha}:#{path}"])],
          not String.contains?(text, <<0>>),
          do: {path, text}

    %{paths: paths, deleted: deleted, lines: lines, diff: show.([]), files: files}
  end

  defp count("-"), do: 0
  defp count(n), do: String.to_integer(n)

  defp message(root, sha), do: root |> git(["log", "-1", "--format=%B", sha]) |> elem(0)

  defp commit_time(root, sha) do
    {out, 0} = git(root, ["log", "-1", "--format=%ct", sha])
    out |> String.trim() |> String.to_integer() |> DateTime.from_unix!()
  end

  defp rev(root, ref) do
    case git(root, ["rev-parse", "-q", "--verify", ref]) do
      {out, 0} -> {:ok, String.trim(out)}
      _ -> {:error, "no #{ref}"}
    end
  end

  defp git(root, args), do: System.cmd("git", ["-C", root | args], stderr_to_stdout: true)

  defp short(sha), do: String.slice(sha, 0, 7)
end
