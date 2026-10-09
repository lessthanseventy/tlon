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
  `answer/3` sends the operator's reply into the pane as keys; `respond/3` is the one door every
  operator post takes — an answer when it names an option of an open prompt, a plain post
  otherwise. A prompt with no `window` is no pane's: the PM's release gate (`Server.Release.PM`),
  whose answer goes to the PM instead of a pane, and which no reconcile closes.

  Detection fails closed: a pane reads as waiting only on a positive match of a harness's own
  dialog — pi-permission-system's cursor-marked `▶ (y) Yes … enter confirm · esc deny`, Claude
  Code's cursor-marked `❯ 1. Yes` list under a `…?` question. A model's own numbered list has no
  cursor; an unknown screen is not-waiting.
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
    pi(lines) || claude(lines)
  end

  # pi-permission-system: `▶ (y) Yes` / `  (s) Yes, allow …` / … and the confirm line.
  @pi_option ~r/^\s*(▶?)\s*\((\w)\)\s+(\S.*)$/u
  @pi_confirm "enter confirm"

  defp pi(lines) do
    matches = for line <- lines, [_, cursor, key, label] <- [Regex.run(@pi_option, line)], do: {cursor, key, label}

    if length(matches) >= 2 and Enum.any?(matches, &(elem(&1, 0) == "▶")) and
         Enum.any?(lines, &String.contains?(&1, @pi_confirm)) do
      %{harness: "pi", summary: pi_summary(lines), options: Enum.map(matches, fn {_, k, l} -> %{key: k, label: l} end)}
    end
  end

  # The dialog names the command it is asking about; that line is the summary.
  defp pi_summary(lines) do
    Enum.find_value(lines, "permission", fn line ->
      case Regex.run(~r/^\s*(?:full )?command\s*:\s*(.+)$/, line) do
        [_, cmd] -> "bash: " <> String.trim(cmd)
        nil -> nil
      end
    end)
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
    tabs = Tmux.list_windows(workspace_id)
    standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

    seen =
      for tab <- tabs, tid = tab.thread_id || standing, is_integer(tid), reduce: MapSet.new() do
        acc ->
          reconcile_safely(workspace_id, tid, tab.name, detect(capture(workspace_id, tab.index)))
          MapSet.put(acc, {tid, tab.name})
      end

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
  The one door for an operator post. A closed thread reopens. When the thread has an open prompt
  and `body` starts with one of its options (the key, or the label — `y`, `n`, `2`, `yes`), it is
  an answer: keys into the pane, a delivered reply on the thread, the prompt resolved. Anything
  else is a plain post, which the switchboard holds until the prompt is resolved.
  """
  def respond(thread_id, author, body) when is_binary(body) do
    # a reply to a closed thread (one opened from history) reopens it first, so its lead is staffed
    _ = Channel.reopen_if_closed(thread_id)

    posted =
      case open_prompt(thread_id) do
        %Message{} = prompt ->
          case pick(prompt, body) do
            nil -> Channel.post(%{thread_id: thread_id, author: author, body: body})
            {key, rest} -> answer(prompt, author, body, key, rest)
          end

        nil ->
          Channel.post(%{thread_id: thread_id, author: author, body: body})
      end

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
  a thread holds as many asks as it has decisions. Answered by id (`answer_ask/3`) or by a reply
  on the thread that names an option. `about` is the thread the decision is about when it isn't
  `thread_id`: when that thread closes the ask is withdrawn (`withdraw_asks_about/1`). `{:ok, prompt}`.
  """
  def ask(thread_id, author, question, [_ | _] = options, about \\ nil) do
    options = options |> Enum.with_index(1) |> Enum.map(fn {label, i} -> %{"key" => "#{i}", "label" => label} end)
    body = "⚑ #{author} asks — #{question}\n" <> Enum.map_join(options, " · ", &"(#{&1["key"]}) #{&1["label"]}")

    %{
      thread_id: thread_id,
      author: author,
      body: body,
      kind: "prompt",
      payload:
        Map.merge(
          %{"ask" => author, "summary" => question, "options" => options},
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
  Withdraw every open ask about `thread_id` (`ask/5`'s `about`): that thread closed, so nothing is
  left to decide. Each asker is told on the thread it asked from, so it stops chasing the decision.
  """
  def withdraw_asks_about(thread_id) do
    from(m in Message,
      where:
        m.kind == "prompt" and is_nil(m.resolved_at) and
          fragment("? ->> 'about'", m.payload) == ^to_string(thread_id)
    )
    |> Repo.all()
    |> Enum.each(fn ask ->
      resolve(ask, "withdrawn: ##{thread_id} closed")

      Channel.post(%{
        thread_id: ask.thread_id,
        author: "tlon",
        reply_to: ask.id,
        body:
          "@#{ask.payload["ask"]} your ask is withdrawn: ##{thread_id} closed, so there is nothing left to decide — “#{ask.payload["summary"]}”"
      })
    end)
  end

  @doc "Answer the ask `id` with one of its option keys (text after the key rides along)."
  def answer_ask(id, author, body) when is_binary(body) do
    case Repo.get(Message, id) do
      %Message{kind: "prompt", payload: %{"ask" => _}, resolved_at: nil} = prompt ->
        case pick(prompt, body) do
          {key, rest} -> answer(prompt, author, body, key, rest)
          nil -> {:error, :no_such_option}
        end

      %Message{kind: "prompt", payload: %{"ask" => _}} ->
        {:error, :answered}

      _ ->
        {:error, :not_found}
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
    text = "@#{asker} #{q} → #{label}" <> if(rest == "", do: "", else: " — #{rest}")

    with {:ok, reply} <- Channel.post(%{thread_id: prompt.thread_id, author: author, body: text, reply_to: prompt.id}) do
      resolve(prompt, "answered: " <> label)
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
    _ = Tmux.send_text(ws, window, keystrokes(p["harness"], key))

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

  defp keystrokes("pi", key), do: key <> key
  defp keystrokes(_harness, key), do: key

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
