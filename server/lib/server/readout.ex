defmodule Server.Readout do
  @moduledoc """
  A thread or a message as plain text, for a terminal or an agent reading from the shell
  (`tlon-cli read`, `tlon-cli message`): every body whole, nothing to parse.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @doc "Thread `id`'s title and state, then its last `n` messages, oldest first."
  def thread(id, n) do
    case Repo.get(Thread, id) do
      nil ->
        "no thread ##{id}"

      t ->
        msgs = Channel.recent_messages(t, n)
        total = Repo.aggregate(from(m in Message, where: m.thread_id == ^id), :count)
        head = "thread ##{t.id} #{t.title} (#{t.state}) · last #{length(msgs)} of #{total}"
        Enum.join([head | Enum.map(msgs, &entry/1)], "\n\n")
    end
  end

  @doc "Message `id` in full: where it is, who and what kind, what it answers, its delivery and resolution, its payload."
  def message(id) do
    case Repo.get(Message, id) do
      nil ->
        "no message ##{id}"

      m ->
        t = Repo.get(Thread, m.thread_id)

        [
          "message ##{m.id} on thread ##{m.thread_id} #{t && t.title}",
          "#{m.author} · #{m.kind} · #{m.created_at}" <> if(m.reply_to, do: " · reply to ##{m.reply_to}", else: ""),
          "delivered: #{m.delivered_at || "not yet"} · resolved: " <>
            if(m.resolved_at, do: "#{m.resolved_at} (#{m.resolution})", else: "no"),
          if(m.payload, do: "payload: " <> JSON.encode!(m.payload)),
          "",
          m.body
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
    end
  end

  defp entry(m) do
    at = m.created_at |> DateTime.to_string() |> String.slice(0, 16)
    body = m.body |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))
    "##{m.id} #{m.author} · #{m.kind} · #{at}\n#{body}"
  end
end
