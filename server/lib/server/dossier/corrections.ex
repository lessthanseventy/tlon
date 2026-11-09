defmodule Server.Dossier.Corrections do
  @moduledoc """
  The operator's own words, heard for a standing call. A correction ("don't do that", "always run
  the gate first", "use ripgrep instead") is a durable preference, and the adapter's
  `detectCorrection` already proposes one as a habit; this side banks it as a `stated` fact the
  moment the operator posts it, so his words reach the store without anyone being told "bank it".
  The detection is the adapter's heuristic (the same signals and bounds), cheap by design: a false
  positive costs one `forget_fact`, and the notice that follows every bank names which.
  """

  alias Server.{Channel, Dossier, Fact, Message, Recall}

  @signals [
    ~r/\bdon'?t\b/i,
    ~r/\b(always|never)\b/i,
    ~r/\binstead\b/i,
    ~r/\bprefer\b/i,
    ~r/\bfrom now on\b/i,
    ~r/^\s*(no|nope|actually|stop)\b/i
  ]

  # below the floor it is an interjection ("ok"), above the ceiling a task, not a habit
  @min 8
  @max 240

  @doc """
  Whether `text` reads as a correction or a durable preference rather than a task: terse, and
  carrying one of the signals. `{:ok, text}` (trimmed) or `:none`.
  """
  @spec detect(String.t()) :: {:ok, String.t()} | :none
  def detect(text) when is_binary(text) do
    text = String.trim(text)
    length = String.length(text)

    if length >= @min and length <= @max and Enum.any?(@signals, &Regex.match?(&1, text)),
      do: {:ok, text},
      else: :none
  end

  @doc """
  Bank a correction among the operator's words as a stated `constraint` on the message's thread,
  and say so there in a notice (`tlon`, waking nobody) that names the fact and how to forget it.
  A message by anyone else, or one that is not a correction, is `:none`.
  """
  @spec heard(Message.t()) :: {:ok, Fact.t()} | :none | {:error, Ecto.Changeset.t()}
  def heard(%Message{} = message) do
    if Channel.operator?(message.author) and match?({:ok, _}, detect(message.body)),
      do: bank(message),
      else: :none
  end

  defp bank(message) do
    with {:ok, fact} <- Dossier.bank_stated_fact(message, %{kind: "constraint"}) do
      Recall.embed_on_write(fact)

      Channel.post(%{
        thread_id: message.thread_id,
        author: "tlon",
        kind: "notice",
        body:
          "banked fact ##{fact.id} from your words: “#{fact.text}” — `tlon-cli forget-fact #{fact.id}` if that is no standing call"
      })

      {:ok, fact}
    end
  end
end
