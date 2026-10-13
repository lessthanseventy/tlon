defmodule Server.Attention do
  @moduledoc """
  Waiting is a first-class state (master plan 2026-09-25, piece A / R2). A coworker sitting on a
  permission prompt or a question is invisible in its thread unless something says so — one sat
  ten minutes on `eval "$(mise activate bash)"` while the thread read "still on it". This derives
  the state from the pane (`detect/1` reads a harness's own dialog off captured tmux text) and
  makes it a ROW: a `prompt` message from `tlon` on the thread, the dialog's options in its
  payload, resolved when the pane moves on or the operator answers. The message IS the state —
  no session column to drift from it — so the rail badge, the shell toast, the web and the API
  all read the same "this thread has an unresolved prompt".

  `tick/0` reconciles every workspace's coworker windows (the poller calls it every few seconds);
  `answer_prompt/3` answers one prompt by its id — the only way any surface answers one — and
  sends a pane's answer in as keys after re-reading the pane; `respond/3` is an operator's plain
  post on a thread, never an answer. A prompt with no `window` is no pane's: the PM's release gate
  (`Server.Release.PM`), whose answer goes to the PM instead of a pane, and which no reconcile closes.

  Detection fails closed: a pane reads as waiting only on a positive match of a harness's own
  dialog — Claude Code's cursor-marked `❯ 1. Yes` list under a `…?` question. A model's own
  numbered list has no cursor; an unknown screen is not-waiting.
  """

  import Ecto.Query

  alias Server.Bus
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  @type option :: %{key: String.t(), label: String.t()}
  @type prompt :: %{harness: String.t(), summary: String.t(), options: [option()]}

  # ---- detection (pure) --------------------------------------------------------------------

  @doc "The waiting dialog in captured pane text, or nil when the pane is not waiting on anyone."
  @spec detect(String.t()) :: prompt() | nil
  def detect(text) when is_binary(text) do
    lines = text |> String.split("\n") |> Enum.map(&String.trim_trailing/1)
    claude(lines)
  end

  # Claude Code: a boxed dialog — `Do you want to proceed?` then `❯ 1. Yes` / `  2. …`. The box
  # border is stripped before matching. Written from the dialog's known shape, not a live capture.
  @cc_option ~r/^\s*(❯?)\s*(\d+)\.\s+(\S.*)$/u

  defp claude(lines) do
    stripped = Enum.map(lines, &(&1 |> String.replace(~r/^\s*│\s?/u, "") |> String.replace(~r/\s*│\s*$/u, "")))
    matches = for line <- stripped, [_, cursor, key, label] <- [Regex.run(@cc_option, line)], do: {cursor, key, label}
    first = Enum.find_index(stripped, &Regex.match?(@cc_option, &1))

    question =
      if first,
        do: stripped |> Enum.take(first) |> Enum.reverse() |> Enum.find(&String.ends_with?(String.trim(&1), "?"))

    if length(matches) >= 2 and Enum.any?(matches, &(elem(&1, 0) == "❯")) and is_binary(question) do
      %{
        harness: "claude",
        summary: String.trim(question),
        options: Enum.map(matches, fn {_, k, l} -> %{key: k, label: l} end)
      }
    end
  end

  # ---- the reconcile ------------------------------------------------------------------------

  @doc "One reconcile over every workspace's coworker windows."
  def tick do
    for %{id: id} <- Workspaces.all(), do: tick(id)
    :ok
  end

  @doc """
  One workspace: every window's pane is read; a waiting pane with no open prompt opens one, a
  pane that moved on resolves its prompt (`answered in the terminal`), a new dialog on the same
  window supersedes the old row, a window that is gone closes what it left open. A window with no
  `@funes_thread` tag belongs to the workspace's standing machine thread.
  """
  def tick(workspace_id) do
    case Tmux.list_windows(workspace_id) do
      # a tmux that can't be asked is no window closed: the next tick reads the panes again
      {:error, _} -> :ok
      tabs -> tick_tabs(workspace_id, tabs)
    end
  end

  defp tick_tabs(workspace_id, tabs) do
    standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

    seen =
      for tab <- tabs, tid = tab.thread_id || standing, is_integer(tid), reduce: MapSet.new() do
        acc ->
          text = capture(workspace_id, tab.index)
          reconcile_safely(workspace_id, tid, tab.name, detect(text))
          quota_safely(workspace_id, tab.agent, "#{tid}/#{tab.name}", text)
          MapSet.put(acc, {tid, tab.name})
      end

    panes =
      for tab <- tabs,
          tid = tab.thread_id || standing,
          is_integer(tid),
          into: MapSet.new(),
          do: "#{tab.agent}/#{tid}/#{tab.name}"

    Server.Shifts.prune(workspace_id, panes)

    # a prompt with no window (the PM's release gate) is no pane's to close
    for prompt <- open_prompts(workspace_id),
        prompt.payload["window"],
        not MapSet.member?(seen, {prompt.thread_id, prompt.payload["window"]}),
        do: resolve(prompt, "window closed")

    :ok
  end

  defp capture(workspace_id, index) do
    case Tmux.run(workspace_id, ["capture-pane", "-p", "-t", Tmux.target(workspace_id, index)]) do
      {out, 0} when is_binary(out) -> out
      _ -> ""
    end
  end

  # one window's row the db refuses (pane text that won't store) doesn't stop the rest of the tick
  defp reconcile_safely(workspace_id, thread_id, window, detected) do
    reconcile(workspace_id, thread_id, window, detected)
  rescue
    e -> require(Logger) && Logger.error("attention #{workspace_id}/#{window}: #{Exception.message(e)}")
  end

  defp reconcile(workspace_id, thread_id, window, detected) do
    case {open_prompt(thread_id, window), detected} do
      {nil, nil} -> :ok
      {nil, prompt} -> open(workspace_id, thread_id, window, prompt)
      {%Message{} = m, nil} -> resolve(m, "answered in the terminal")
      {%Message{payload: %{"summary" => s}}, %{summary: s}} -> :ok
      {%Message{} = m, prompt} -> resolve(m, "superseded") && open(workspace_id, thread_id, window, prompt)
    end
  end

  # The prompt row: authored by tlon, DELIVERED at birth — it is the operator's to answer, and the
  # switchboard must never type it back into the very pane that is waiting.
  defp open(workspace_id, thread_id, window, %{harness: harness, summary: summary, options: options}) do
    body = "⚑ waiting on you — #{summary}\n" <> Enum.map_join(options, " · ", &"(#{&1.key}) #{&1.label}")

    payload = %{
      "harness" => harness,
      "summary" => summary,
      "options" => Enum.map(options, &%{"key" => &1.key, "label" => &1.label}),
      "window" => window,
      "workspace_id" => workspace_id
    }

    %{thread_id: thread_id, author: "tlon", body: body, kind: "prompt", payload: payload}
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, now())
    |> Repo.insert!()
    |> tap(&Bus.broadcast({:message_posted, &1}))
  end

  @doc "Close a prompt with how it ended; a thread topic event repaints every client."
  def resolve(%Message{kind: "prompt"} = prompt, resolution) do
    prompt
    |> Message.resolve_changeset(resolution)
    |> Repo.update!()
    |> tap(&Bus.broadcast({:prompt_resolved, &1}))
  end

  # ---- reads --------------------------------------------------------------------------------

  @doc "The thread's newest unresolved prompt (on `window` when given), or nil."
  def open_prompt(thread_id, window \\ nil) do
    from(m in Message,
      where: m.thread_id == ^thread_id and m.kind == "prompt" and is_nil(m.resolved_at),
      order_by: [desc: m.id],
      limit: 1
    )
    |> scope_window(window)
    |> Repo.one()
  end

  defp scope_window(query, nil), do: query
  defp scope_window(query, window), do: where(query, [m], fragment("? ->> 'window'", m.payload) == ^window)

  @doc """
  Is a pane on this thread sitting on a dialog? A prompt no pane holds (the release gate) doesn't
  count: nothing typed into the thread could answer it by accident.
  """
  def waiting?(thread_id) do
    Repo.exists?(
      from m in Message,
        where:
          m.thread_id == ^thread_id and m.kind == "prompt" and is_nil(m.resolved_at) and
            fragment("? ->> 'window' IS NOT NULL", m.payload)
    )
  end

  @doc "Every unresolved prompt on the workspace's open threads."
  def open_prompts(workspace_id) do
    Repo.all(
      from(m in Message,
        join: t in Thread,
        on: t.id == m.thread_id,
        where: t.workspace_id == ^workspace_id and m.kind == "prompt" and is_nil(m.resolved_at)
      )
    )
  end

  @doc "The open prompts keyed by thread — one query for a sidebar: `%{thread_id => %{id, summary, options}}`."
  def open_prompts_by_thread do
    from(m in Message,
      where: m.kind == "prompt" and is_nil(m.resolved_at) and fragment("NOT (? \\? 'ask')", m.payload),
      order_by: [asc: m.id]
    )
    |> Repo.all()
    |> Map.new(&{&1.thread_id, %{id: &1.id, summary: &1.payload["summary"], options: &1.payload["options"]}})
  end

  @doc "Every unanswered ask (`ask/4`), oldest first."
  def open_asks do
    Repo.all(
      from m in Message,
        where: m.kind == "prompt" and is_nil(m.resolved_at) and fragment("? \\? 'ask'", m.payload),
        order_by: [asc: m.id]
    )
  end

  # ---- answering ----------------------------------------------------------------------------

  @doc """
  The door for an operator post on a thread: a closed thread reopens, the post is a plain post
  (the switchboard holds it while a pane on the thread sits on a dialog), and a worker's question
  is settled. It never answers a prompt — an answer names its prompt (`answer_prompt/3`), so a key
  meant for one prompt can't land in another on the same thread.
  """
  def respond(thread_id, author, body) when is_binary(body) do
    # a reply to a closed thread (one opened from history) reopens it first, so its lead is staffed
    _ = Channel.reopen_if_closed(thread_id)

    posted = Channel.post(%{thread_id: thread_id, author: author, body: body})
    with {:ok, _} <- posted, do: answered(thread_id)
    posted
  end

  @doc """
  A worker's question for the operator — the `ask_operator` tool's door. The question is posted as
  the worker and the thread parks on the operator (`awaiting`), the field every waiting-on-you
  surface already reads (the office's inbox, the shell's inbox, its toasts); the operator's reply
  clears it (`respond/3`). `{:ok, message}`.
  """
  def ask(thread_id, author, text) do
    operator = Application.get_env(:server, :operator, "andrew")

    with {:ok, message} <- Channel.post(%{thread_id: thread_id, author: author, body: text}),
         %Thread{} = thread <- Repo.get(Thread, thread_id),
         {:ok, _} <- thread |> Ecto.Changeset.change(awaiting: operator) |> Repo.update() do
      {:ok, message}
    end
  end

  @doc """
  A decision with its answers attached — `ask_operator(question, options)`'s door. One pane-less
  `prompt` per decision (payload `ask: author`), keyed `1`, `2`, …; the thread does not park, and
  a thread holds as many asks as it has decisions. Answered by id (`answer_prompt/3`); a reply on
  the thread is a reply, not an answer. `about` is the thread the decision is about when it isn't
  `thread_id`: when that thread closes the ask is withdrawn (`withdraw_asks_about/1`). An ask by the
  thread's lead is marked `led`, so an answer after the thread changed hands goes to its lead now.
  `extra`'s `"for"` names the coworker who has to act on the answer when it isn't the asker; kept
  only when it names another coworker on the thread's bench, it gets the answer itself.
  `{:ok, prompt}`.
  """
  def ask(thread_id, author, question, [_ | _] = options, about \\ nil, extra \\ %{}) do
    options = options |> Enum.with_index(1) |> Enum.map(fn {label, i} -> %{"key" => "#{i}", "label" => label} end)
    extra = actor(extra, thread_id, author)
    body = "⚑ #{author} asks — #{question}\n" <> Enum.map_join(options, " · ", &"(#{&1["key"]}) #{&1["label"]}")

    %{
      thread_id: thread_id,
      author: author,
      body: body,
      kind: "prompt",
      payload:
        Map.merge(
          Map.merge(
            %{
              "ask" => author,
              "summary" => question,
              "options" => options,
              "led" => Channel.thread_lead(thread_id) == author
            },
            extra
          ),
          if(about, do: %{"about" => about}, else: %{})
        )
    }
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, now())
    |> Repo.insert()
    |> case do
      {:ok, m} -> {:ok, tap(m, &Bus.broadcast({:message_posted, &1}))}
      error -> error
    end
  end

  @doc """
  Withdraw every open ask on `thread_id` or about it (`ask/5`'s `about`): that thread closed, so
  nothing is left to decide. An asker who asked from another thread is told there, so it stops
  chasing the decision.
  """
  def withdraw_asks_about(thread_id) do
    from(m in Message,
      where:
        m.kind == "prompt" and is_nil(m.resolved_at) and
          (fragment("? ->> 'about'", m.payload) == ^to_string(thread_id) or
             (m.thread_id == ^thread_id and fragment("? \\? 'ask'", m.payload)))
    )
    |> Repo.all()
    |> Enum.each(fn ask ->
      resolve(ask, "withdrawn: ##{thread_id} closed")

      if ask.thread_id != thread_id,
        do:
          Channel.post(%{
            thread_id: ask.thread_id,
            author: "tlon",
            reply_to: ask.id,
            body:
              "@#{ask.payload["ask"]} your ask is withdrawn: ##{thread_id} closed, so there is nothing left to decide — “#{ask.payload["summary"]}”"
          })
    end)
  end

  @doc """
  Answer the open prompt `id` — a pane's dialog, an ask, the release gate — with one of its
  options (the key or the label; text after it rides along). A pane's dialog is typed into only
  while the pane still shows it: the screen is read again first, and a dialog gone from it is
  `{:error, :not_showing}` (the next tick settles the row). `{:ok, reply}`, or `{:error,
  :not_found | :answered | :no_such_option | :not_showing}`.
  """
  def answer_prompt(id, author, body) when is_binary(body) do
    with %Message{kind: "prompt", resolved_at: nil} = prompt <- Repo.get(Message, id),
         {:ok, key, rest} <- option(prompt, body),
         :ok <- still_showing(prompt) do
      prompt |> answer(author, body, key, rest) |> settling(prompt.thread_id)
    else
      %Message{kind: "prompt"} -> {:error, :answered}
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp option(prompt, body) do
    case pick(prompt, body) do
      {key, rest} -> {:ok, key, rest}
      nil -> {:error, :no_such_option}
    end
  end

  defp still_showing(%Message{payload: %{"window" => window, "workspace_id" => ws, "summary" => summary}}) do
    case Tmux.run(ws, ["capture-pane", "-p", "-t", Tmux.target(ws, "=" <> window)]) do
      {out, 0} when is_binary(out) ->
        if match?(%{summary: ^summary}, detect(out)), do: :ok, else: {:error, :not_showing}

      _ ->
        {:error, :not_showing}
    end
  end

  defp still_showing(_paneless), do: :ok

  defp settling({:ok, _} = posted, thread_id) do
    answered(thread_id)
    posted
  end

  defp settling(error, _thread_id), do: error

  # an offer to switch crews (Server.Shifts): an answer naming a crew puts it on before the ask is
  # resolved, so a switch refused (its crew gone since) leaves it open to answer again; the last
  # answer stays
  defp take_offer(%{"switch" => offer}, key) do
    case Enum.at(offer["crews"], String.to_integer(key) - 1) do
      nil -> :ok
      crew -> Server.Shifts.take(offer, crew)
    end
  end

  defp take_offer(_payload, _key), do: :ok

  # an ask for another coworker goes to them, whoever leads; an asker the shift took off the bench
  # can't act on the answer: it goes to whoever leads the thread now
  defp addressee(_thread_id, asker, %{"for" => actor}) when is_binary(actor), do: "@#{actor} (#{asker} asked for you)"

  defp addressee(thread_id, asker, %{} = payload) do
    led = payload["led"]

    with %Thread{workspace_id: ws} when not is_nil(ws) <- Repo.get(Thread, thread_id),
         true <- Enum.any?(Server.Workspaces.bench_all(ws), &(&1.name == asker)),
         lead when is_binary(lead) and lead != asker <- Channel.thread_lead(thread_id) do
      cond do
        not Enum.any?(Server.Workspaces.bench(ws), &(&1.name == asker)) -> "@#{lead} (#{asker} asked, now off shift)"
        led -> "@#{lead} (#{asker} asked, no longer leads it)"
        true -> "@#{asker}"
      end
    else
      _ -> "@#{asker}"
    end
  end

  # A reply settles a worker's question. A workline standing at its gate (`Workline.at_gate?/2`) is
  # waiting on an approval, which only `approve` gives — a reply there is just a reply.
  defp answered(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{awaiting: awaiting} = thread when not is_nil(awaiting) ->
        if thread.stage && Server.Workline.at_gate?(thread),
          do: :ok,
          else: thread |> Ecto.Changeset.change(awaiting: nil) |> Repo.update()

      _ ->
        :ok
    end
  end

  # An ask's reply may lead with the label and say more: `go after the cut`.
  defp pick(%Message{payload: %{"ask" => _, "options" => options}} = prompt, body) do
    trimmed = String.trim(body)

    Enum.find_value(options, fn %{"key" => key, "label" => label} ->
      case Regex.run(~r/^#{Regex.escape(label)}(?:\s+(.*))?$/is, trimmed) do
        [_] -> {key, ""}
        [_, rest] -> {key, rest}
        nil -> nil
      end
    end) || pick_key(prompt, trimmed)
  end

  defp pick(prompt, body), do: pick_key(prompt, String.trim(body))

  # `y` / `n` / `2` / `yes` / `No, provide reason` — the first word (or the whole label) picks.
  defp pick_key(%Message{payload: %{"options" => options}}, body) do
    trimmed = String.trim(body)

    {first, rest} =
      case String.split(trimmed, ~r/\s+/, parts: 2) do
        [first, rest] -> {first, rest}
        [first] -> {first, ""}
      end

    Enum.find_value(options, fn %{"key" => key, "label" => label} ->
      cond do
        String.downcase(first) == String.downcase(key) -> {key, rest}
        String.downcase(trimmed) == String.downcase(label) -> {key, ""}
        true -> nil
      end
    end)
  end

  # An ask is no pane's: the answer goes to the asker as a post the switchboard delivers.
  defp answer(
         %Message{payload: %{"ask" => asker, "summary" => q, "options" => opts}} = prompt,
         author,
         _body,
         key,
         rest
       ) do
    label = Enum.find_value(opts, &(&1["key"] == key && &1["label"]))

    to = addressee(prompt.thread_id, asker, prompt.payload)
    text = "#{to} #{q} → #{label}" <> if(rest == "", do: "", else: " — #{rest}")
    # a reply wakes the prompt's author: answered to someone else, the @mention alone delivers it
    reply_to = if to == "@#{asker}", do: prompt.id

    with :ok <- take_offer(prompt.payload, key),
         {:ok, reply} <- Channel.post(%{thread_id: prompt.thread_id, author: author, body: text, reply_to: reply_to}) do
      resolve(Repo.get!(Message, prompt.id), "answered: " <> label)
      {:ok, reply}
    end
  end

  # The release gate is no pane's: the answer is the PM's to act on (`Server.Release.PM.answered/2`).
  defp answer(%Message{payload: %{"release" => _}} = prompt, author, body, key, _rest) do
    reply = insert_answer(prompt, author, body)
    Server.Release.PM.answered(prompt, key)
    {:ok, reply}
  end

  # pi confirms a letter by pressing it again; Claude Code takes the number outright. Free text
  # after the key (a reason, a redirection) follows as its own burst, then Enter.
  defp answer(%Message{payload: p} = prompt, author, body, key, rest) do
    ws = p["workspace_id"]
    window = "=" <> p["window"]
    _ = Tmux.send_text(ws, window, key)

    if rest != "" do
      Process.sleep(Application.get_env(:server, :attention_settle_ms, 300))
      _ = Tmux.send_text(ws, window, rest)
      _ = Tmux.submit(ws, window)
    end

    {:ok, insert_answer(prompt, author, body)}
  end

  # delivered HERE: the answer has gone where it was for, so the switchboard must not type it again
  defp insert_answer(prompt, author, body) do
    reply =
      %{thread_id: prompt.thread_id, author: author, body: body, reply_to: prompt.id}
      |> Message.post_changeset()
      |> Ecto.Changeset.put_change(:delivered_at, now())
      |> Repo.insert!()

    resolve(prompt, "answered: " <> String.trim(body))
    Bus.broadcast({:message_posted, reply})
    reply
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  # a fault switching shifts doesn't stop the rest of the tick either
  defp quota_safely(workspace_id, agent, pane, text) do
    Server.Shifts.quota_check(workspace_id, agent, pane, text)
  rescue
    e ->
      require(Logger) &&
        Logger.error("attention #{workspace_id}: shift switch on a usage limit failed: #{Exception.message(e)}")
  end

  defp actor(%{"for" => name} = extra, thread_id, asker) do
    with true <- is_binary(name) and name != asker,
         %Thread{workspace_id: ws} when not is_nil(ws) <- Repo.get(Thread, thread_id),
         true <- Enum.any?(Workspaces.bench_all(ws), &(&1.name == name)) do
      extra
    else
      _ -> Map.delete(extra, "for")
    end
  end

  defp actor(extra, _thread_id, _asker), do: extra
end
