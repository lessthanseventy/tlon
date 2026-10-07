defmodule Server.Office.Needs do
  @moduledoc """
  Everything waiting on the operator, as ONE list — derived from the state that already says so,
  never a second record that could drift from it. Each item is
  `%{key, kind, level, thread_id, workspace_id, title, text, at, options}`:

    * **blocking** — work has stopped until the operator acts:
      `gate` (a workline at its gate: approve), `question` (a coworker asked: reply), `dialog` (a pane
      sits on a prompt: pick an option), `verify_failed` (a workline whose last gate run was red);
    * **decide** — wants the operator, nothing waits on it: `mention` (an @operator on an open thread
      with no reply from them since), `suggestion` (the corkboard's suggestion box), `rollout` (what a
      merge could not roll out itself).

  Blocking first, then to decide; oldest first within each. An item leaves the list when the thing
  behind it is resolved — approved, answered, filed — not when it is looked at.
  """
  import Ecto.Query

  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @mention_days 7

  @doc "Every item waiting on the operator, across the workspaces."
  def list do
    operator = Application.get_env(:server, :operator, "andrew")
    open = Repo.all(from t in Thread, where: t.state == "open")
    prompts = Server.Attention.open_prompts_by_thread()

    blocking = waits(open, prompts) ++ red_verifies(open)
    decide = mentions(open, operator) ++ suggestions(open) ++ rollout()

    Enum.sort_by(blocking, & &1.at) ++ Enum.sort_by(decide, & &1.at)
  end

  # a pane on a prompt is a dialog; else an `awaiting` is a gate (workline at its gate) or a question
  defp waits(open, prompts) do
    for t <- open, item = wait(t, prompts[t.id]), item, do: item
  end

  defp wait(t, %{} = prompt),
    do: item("dialog", "blocking", t, prompt.summary, prompt_at(prompt.id), %{options: prompt.options})

  defp wait(%Thread{awaiting: nil}, nil), do: nil

  defp wait(%Thread{stage: stage} = t, nil) when not is_nil(stage) do
    if Server.Workline.at_gate?(t),
      do: item("gate", "blocking", t, "#{t.slug} waits at #{stage} for your approval", t.created_at),
      else: question(t)
  end

  defp wait(t, nil), do: question(t)

  # the question is the newest message from someone other than the operator
  defp question(t) do
    operator = Application.get_env(:server, :operator, "andrew")

    m =
      Repo.one(
        from m in Message,
          where: m.thread_id == ^t.id and m.author != ^operator,
          order_by: [desc: m.id],
          limit: 1
      )

    item("question", "blocking", t, (m && m.body) || "waits on you", (m && m.created_at) || t.created_at)
  end

  defp prompt_at(id), do: Repo.one(from m in Message, where: m.id == ^id, select: m.created_at)

  # a workline sitting at verify whose newest verify run was red
  defp red_verifies(open) do
    for %Thread{stage: "verify", slug: slug} = t <- open,
        %{kind: "check_failed"} = e <- [last_verify(slug)],
        do:
          item(
            "verify_failed",
            "blocking",
            t,
            "verify is red: #{e.detail["cmd"]} (exit #{e.detail["exit"]})",
            e.created_at
          )
  end

  defp last_verify(slug) do
    Repo.one(
      from e in Server.Event,
        where: e.correlation == ^"workline:#{slug}:verify" and e.kind in ["check_passed", "check_failed"],
        order_by: [desc: e.id],
        limit: 1
    )
  end

  # an @operator nobody has answered: the newest such message per open thread, with no operator
  # message after it
  defp mentions(open, operator) do
    since = DateTime.add(DateTime.utc_now(), -@mention_days * 86_400, :second)
    ids = Enum.map(open, & &1.id)
    by_id = Map.new(open, &{&1.id, &1})
    like = "%@#{operator}%"

    from(m in Message,
      where: m.thread_id in ^ids and m.author != ^operator and ilike(m.body, ^like) and m.created_at > ^since,
      order_by: [desc: m.id]
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.thread_id)
    # a thread already waiting on the operator is on the list as its question, not twice
    |> Enum.reject(&(by_id[&1.thread_id].awaiting != nil or answered?(&1, operator)))
    |> Enum.map(&item("mention", "decide", by_id[&1.thread_id], "#{&1.author}: #{&1.body}", &1.created_at))
  end

  defp answered?(m, operator),
    do: Repo.exists?(from r in Message, where: r.thread_id == ^m.thread_id and r.author == ^operator and r.id > ^m.id)

  defp suggestions(open) do
    workspaces = open |> Enum.map(& &1.workspace_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    for ws <- workspaces, s <- Server.Office.Corkboard.suggestions(ws) do
      %{
        key: "suggestion:#{ws}:#{s.id}",
        kind: "suggestion",
        level: "decide",
        thread_id: nil,
        workspace_id: ws,
        title: "suggestion from #{s.author}",
        text: s.body,
        at: DateTime.from_unix!(s.at),
        options: nil,
        ref: s.id
      }
    end
  end

  defp rollout do
    for n <- Server.Rollout.pending() do
      %{
        key: "rollout:#{n.id}",
        kind: "rollout",
        level: "decide",
        thread_id: nil,
        workspace_id: nil,
        title: "rollout",
        text: n.text,
        at: DateTime.from_unix!(n.at),
        options: nil,
        ref: n.id
      }
    end
  end

  defp item(kind, level, %Thread{} = t, text, at, extra \\ %{}) do
    Map.merge(
      %{
        key: "#{kind}:#{t.id}",
        kind: kind,
        level: level,
        thread_id: t.id,
        workspace_id: t.workspace_id,
        title: t.title,
        text: text,
        at: at,
        options: nil,
        ref: nil
      },
      extra
    )
  end
end
