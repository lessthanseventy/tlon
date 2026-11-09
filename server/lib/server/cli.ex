defmodule Server.CLI do
  @moduledoc """
  The operator verbs `scripts/tlon-cli.sh` runs inside the live node (`bin/server rpc`), one function
  each. A verb answers `{:ok, text}` or `{:error, text}`; `out/2` prints the text and raises on an
  error, which is what makes `rpc` exit non-zero (the expression runs in the service node, so a halt
  would stop the service). A refusal the verb has always exited 0 on is `{:ok, text}`.
  """

  alias Server.{Attention, Channel, Dossier, Repo, Tickets, Workline}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @fields %{"status" => :status, "title" => :title, "body" => :body, "priority" => :priority}

  @close_kinds %{"superseded" => :superseded, "resolved" => :resolved, "abandoned" => :abandoned}

  @doc """
  Prints a verb's text and raises on `{:error, _}`. `device` is where an error's text goes
  (`:stdio`, or `:stderr` for the verbs whose refusal never reached stdout).
  """
  @spec out(result(), :stdio | :stderr) :: :ok
  def out(result, device \\ :stdio)
  def out({:ok, text}, _device), do: IO.puts(text)

  def out({:error, text}, device) do
    IO.puts(device, text)
    raise "refused"
  end

  @doc "Files a ticket; `project` is an id or nil."
  @spec ticket_file(integer(), integer() | nil, String.t(), String.t()) :: result()
  def ticket_file(workspace, project, title, body) do
    file_ticket(%{workspace_id: workspace, project_id: project, title: title, body: body}, "ticket")
  end

  @doc "Files an epic."
  @spec epic_new(integer(), String.t(), String.t()) :: result()
  def epic_new(workspace, title, body) do
    file_ticket(%{workspace_id: workspace, kind: "epic", title: title, body: body}, "epic")
  end

  @doc "Ties tickets to an epic, all or nothing."
  @spec epic_add(integer(), [integer()]) :: result()
  def epic_add(epic, ticket_ids) do
    case Tickets.adopt(epic, ticket_ids) do
      {:ok, ids} -> {:ok, "epic ##{epic} now holds #{length(ids)} ticket(s)"}
      {:error, {id, cs}} -> {:error, "refused ##{id}: #{inspect(cs.errors)}"}
    end
  end

  @doc "Sends a ticket to its workspace's manager to staff."
  @spec ticket_route(integer()) :: result()
  def ticket_route(id) do
    with_ticket(id, fn t ->
      case Tickets.route(t) do
        {:ok, %{routed_to: m}} -> {:ok, "ticket ##{id} sent to #{m}"}
        {:ok, %{started: th}} -> {:ok, "no manager: ticket ##{id} started as thread ##{th.id}"}
        {:error, why} -> {:error, "refused: #{inspect(why)}"}
      end
    end)
  end

  @doc "Starts a ticket as a thread, handed to an agent id or else the workspace's lead."
  @spec ticket_start(integer(), integer() | nil) :: result()
  def ticket_start(id, agent \\ nil) do
    with_ticket(id, fn t ->
      case Tickets.start_thread(t, agent) do
        {:ok, th} -> {:ok, "started ticket ##{id} as thread ##{th.id}"}
        {:error, why} -> {:error, "refused: #{reason(why)}"}
      end
    end)
  end

  @doc "Claims a ticket worked by hand for `who`."
  @spec ticket_claim(integer(), String.t()) :: result()
  def ticket_claim(id, who) do
    with_ticket(id, fn t ->
      case Tickets.claim(t, who) do
        {:ok, _} -> {:ok, "ticket ##{id} claimed by #{who}"}
        {:error, why} -> {:error, "refused: #{reason(why)}"}
      end
    end)
  end

  @doc "Sets one field (`status`, `title`, `body` or `priority`) of a ticket."
  @spec ticket_set(integer(), String.t(), String.t()) :: result()
  def ticket_set(id, field, value) when is_map_key(@fields, field) do
    with_ticket(id, fn t ->
      case Tickets.update(t, %{Map.fetch!(@fields, field) => value}) do
        {:ok, _} -> {:ok, "ticket ##{id} #{field} set"}
        {:error, cs} -> {:error, "refused: #{inspect(cs.errors)}"}
      end
    end)
  end

  @doc "Deletes a ticket."
  @spec ticket_delete(integer()) :: result()
  def ticket_delete(id) do
    with_ticket(id, fn t ->
      {:ok, _} = Tickets.remove(t)
      {:ok, "deleted ticket ##{id}"}
    end)
  end

  @doc "Tombstones a fact: out of every recall surface, row kept."
  @spec forget_fact(integer()) :: result()
  def forget_fact(id) do
    case Repo.get(Server.Fact, id) do
      nil ->
        {:ok, "no fact ##{id}"}

      f ->
        {:ok, _} = Dossier.forget_fact(f)
        {:ok, "forgot fact ##{id} — #{f.text}"}
    end
  end

  @doc "Closes a stack issue, recording its resolution (or none)."
  @spec resolve_issue(integer(), String.t() | nil) :: result()
  def resolve_issue(id, resolution \\ nil) do
    case Repo.get(Server.Issue, id) do
      nil ->
        {:ok, "no issue ##{id}"}

      i ->
        {:ok, _} = Dossier.resolve_issue(i, resolution)
        {:ok, "resolved issue ##{id} — #{i.summary}"}
    end
  end

  @doc "Queues a reviewed PR in the merge queue."
  @spec land_pr(integer(), String.t(), String.t()) :: result()
  def land_pr(pr, branch, author) do
    case Server.PRLanding.queue(Server.Profiles.tlon_root(), pr, branch, author) do
      {:ok, _} ->
        {:ok, "queued: PR ##{pr} (#{branch}) is in the merge queue — its outcome is posted on its review's thread"}

      {:error, why} ->
        {:error, "refused: " <> reason(why)}
    end
  end

  @doc "The newest review verdict on a branch, as JSON (`null` when there is none)."
  @spec branch_review(String.t()) :: result()
  def branch_review(branch) do
    review =
      case Server.BranchReview.latest(branch) do
        nil -> nil
        r -> Map.delete(r, :at)
      end

    {:ok, Jason.encode!(review)}
  end

  @doc "Advances a workline past its stage; with a `from` stage, only from that one."
  @spec advance(integer(), String.t()) :: result()
  def advance(id, from) do
    case Repo.get(Server.Thread, id) do
      nil ->
        {:ok, "no thread ##{id}"}

      %{stage: s} when from != "" and s != from ->
        {:ok, "not advanced — thread ##{id} is at #{s} now, not #{from}"}

      t ->
        case Workline.advance(t) do
          {:ok, a} -> {:ok, "advanced — thread ##{id} now at #{a.stage}"}
          {:awaiting, a} -> {:ok, "gated at #{a.stage} — awaiting #{a.awaiting}"}
          {:error, why} -> {:ok, "refused: #{inspect(why)}"}
        end
    end
  end

  @doc "Moves a workline back to `stage` (spec, plan or build) on its own branch."
  @spec send_back(integer(), String.t(), String.t(), boolean()) :: result()
  def send_back(id, stage, why, unqueue) do
    with_thread(id, fn t ->
      case Workline.send_back(t, stage, why, Server.OperatorConfig.operator(), unqueue: unqueue) do
        {:ok, b} -> {:ok, "sent back — thread ##{id} now at #{b.stage}, led by #{Channel.thread_lead(b.id)}"}
        {:error, why} -> {:error, "refused: #{inspect(why)}"}
      end
    end)
  end

  @doc "Sends a red verify back to build on the same branch with its finding."
  @spec red_verify(integer(), String.t()) :: result()
  def red_verify(id, finding) do
    with_thread(id, fn t ->
      case Workline.red_verify(t, finding) do
        {:ok, b} -> {:ok, "back to build — thread ##{id}, led by #{Channel.thread_lead(b.id)}"}
        {:error, why} -> {:ok, "left as is: #{inspect(why)}"}
      end
    end)
  end

  @doc "Records verify-stage check evidence, correlated `workline:<slug>:verify`."
  @spec record_verify(integer(), String.t(), integer(), String.t(), String.t()) :: result()
  def record_verify(id, slug, exit_code, cmd, tail) do
    {:ok, e} =
      Dossier.record_check(%{
        thread_id: id,
        cmd: cmd,
        exit: exit_code,
        tail: tail,
        correlation: "workline:#{slug}:verify"
      })

    {:ok, "recorded ##{e.id} #{e.kind}"}
  end

  @doc "Posts to a thread as the operator."
  @spec post(integer(), String.t()) :: result()
  def post(id, body) do
    op = Server.OperatorConfig.operator()
    {:ok, m} = Attention.said(id, op, body)
    {:ok, "posted ##{m.id} to thread ##{id} as #{op}"}
  end

  @doc "Posts to a thread as an outside citizen; a notice wakes nobody."
  @spec post_as(integer(), String.t(), String.t(), boolean()) :: result()
  def post_as(id, citizen, body, notice) do
    case Server.Outside.post(id, citizen, body, notice: notice) do
      {:ok, m} -> {:ok, "posted ##{m.id} to thread ##{id} as #{citizen}"}
      {:error, why} -> {:error, "refused: #{inspect(why)}"}
    end
  end

  @doc "Posts to a thread as tlon, the server's own voice."
  @spec note(integer(), String.t()) :: result()
  def note(id, body) do
    {:ok, m} = Channel.post(%{thread_id: id, author: "tlon", body: body})
    {:ok, "posted ##{m.id} to thread ##{id} as tlon"}
  end

  @doc "Answers one prompt by its id, as the operator."
  @spec answer(integer(), String.t()) :: result()
  def answer(prompt, body) do
    op = Server.OperatorConfig.operator()

    case Attention.answer_prompt(prompt, op, body) do
      {:ok, m} -> {:ok, "answered prompt ##{prompt} as #{op} (##{m.id})"}
      {:error, why} -> {:error, "refused: #{why}"}
    end
  end

  @doc "Closes a thread; an unmerged workline needs a `kind` (superseded, resolved or abandoned) and its why."
  @spec close_thread(integer(), String.t() | nil, String.t()) :: result()
  def close_thread(id, kind, why) when is_nil(kind) or is_map_key(@close_kinds, kind) do
    reason = if kind, do: {Map.fetch!(@close_kinds, kind), why}

    with_thread(id, fn t ->
      case Channel.close_as(t, reason) do
        {:ok, _} ->
          {:ok, "closed thread ##{id} — #{t.title}"}

        {:tracked, w} ->
          {:ok, "not closed: ##{id} holds unmerged work — tracked as workline #{w.slug} at build"}

        {:error, :why_closed} ->
          {:error,
           "refused: ##{id} is a workline that hasn't merged — close-thread #{id} superseded <pr-or-commit> | resolved <why> | abandoned <why>"}

        {:error, why} ->
          {:error, "refused: #{inspect(why)}"}
      end
    end)
  end

  @doc "Reopens a closed thread."
  @spec reopen(integer()) :: result()
  def reopen(id) do
    with_thread(id, fn t ->
      case Workline.reopen(t) do
        {:ok, r} -> {:ok, "reopened thread ##{id} — #{r.title}#{if r.stage, do: " (#{r.stage})"}"}
        other -> {:error, "reopened thread ##{id}, but: #{inspect(other)}"}
      end
    end)
  end

  @doc "Hands a running thread to another coworker and staffs it now."
  @spec hand_off(integer(), String.t()) :: result()
  def hand_off(id, handle) do
    case Server.Staffing.hand_off(id, handle) do
      {:ok, t} ->
        Task.start(fn -> Server.Staffing.pass(t.workspace_id) end)
        {:ok, "handed thread ##{id} to #{handle}"}

      {:error, why} ->
        {:error, "refused: #{inspect(why)}"}
    end
  end

  @doc "Completes a workline's parked gate; `opts` takes `skip_qa:` and `as:`."
  @spec approve(integer(), keyword()) :: result()
  def approve(id, opts) do
    case Repo.get(Server.Thread, id) do
      nil ->
        {:ok, "no thread ##{id}"}

      t ->
        case Workline.approve(t, opts) do
          {:ok, a} -> {:ok, "approved — thread ##{id} now at #{a.stage}"}
          {:error, why} -> {:ok, "refused: #{inspect(why)}"}
        end
    end
  end

  @doc "Hard-deletes a thread; its facts survive unlinked."
  @spec delete_thread(integer()) :: result()
  def delete_thread(id) do
    case Repo.get(Server.Thread, id) do
      nil ->
        {:ok, "no thread ##{id}"}

      t ->
        case Channel.delete_thread(t) do
          {:ok, _} -> {:ok, "deleted thread ##{id} — #{t.title}"}
          {:error, why} -> {:ok, "refused: #{inspect(why)}"}
        end
    end
  end

  @doc "Opens a workline at stage intent."
  @spec workline(String.t(), String.t()) :: result()
  def workline(title, slug) do
    case Workline.open(%{title: title, slug: slug}) do
      {:ok, t} -> {:ok, "workline ##{t.id} #{t.slug} at #{t.stage} — folder work/#{t.slug}/"}
      {:error, cs} -> {:ok, "refused: #{inspect(cs.errors)}"}
    end
  end

  @doc "Promotes a plain thread into a workline at build."
  @spec track(integer()) :: result()
  def track(id) do
    case Repo.get(Server.Thread, id) do
      nil ->
        {:ok, "no thread ##{id}"}

      t ->
        case Workline.promote(t) do
          {:ok, w} -> {:ok, "tracked — thread ##{id} is workline #{w.slug} at #{w.stage}"}
          {:error, why} -> {:ok, "refused: #{inspect(why)}"}
        end
    end
  end

  @doc "Turns a feature flag on or off for everyone."
  @spec flag(String.t(), boolean()) :: result()
  def flag(name, on) do
    case Server.Flags.set(name, on) do
      {:ok, f} -> {:ok, "#{f.name} is now #{if on, do: "on", else: "off"}"}
      {:error, why} -> {:ok, why}
    end
  end

  @doc "The office's stop controls: `pencils_down`, `lights_out` or `back_to_work`."
  @spec pause(String.t()) :: result()
  def pause("pencils_down"), do: pause_state(Server.Pause.pencils_down())
  def pause("lights_out"), do: pause_state(Server.Pause.lights_out())
  def pause("back_to_work"), do: pause_state(Server.Pause.back_to_work())

  defp pause_state({:ok, state}), do: {:ok, "the office: #{state}"}

  defp file_ticket(attrs, noun) do
    case Tickets.file(attrs) do
      {:ok, t} -> {:ok, "filed #{noun} ##{t.id} — #{t.title}"}
      {:error, cs} -> {:error, "refused: #{inspect(cs.errors)}"}
    end
  end

  defp with_ticket(id, fun) do
    case Tickets.get(id) do
      nil -> {:error, "no ticket ##{id}"}
      t -> fun.(t)
    end
  end

  defp with_thread(id, fun) do
    case Repo.get(Server.Thread, id) do
      nil -> {:error, "no thread ##{id}"}
      t -> fun.(t)
    end
  end

  defp reason(why) when is_binary(why), do: why
  defp reason(why), do: inspect(why)
end
