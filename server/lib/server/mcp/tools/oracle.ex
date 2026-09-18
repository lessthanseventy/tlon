defmodule Server.MCP.Tool.ConsultOracle do
  @moduledoc """
  A second opinion from the OTHER bucket (Amp's Oracle, field survey §4 adopt #6): a coworker on
  the Claude plan asks a model on the ollama plan, and vice versa — one tool call instead of a
  paste into another chat, and the cost lands on the bucket the caller is NOT draining. The
  question and the answer are posted to the thread as `oracle`, so the record keeps the exchange
  (the thread IS the record). CLI + model per side are config (`:oracle_<side>_cmd/_model`);
  vendor is never design.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.ModelCli

  schema do
    field :question, :string, required: true, description: "The decision or claim to get a second read on"

    field :context, :string,
      description: "What the other model needs to know — code, constraints, what you already concluded"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    side = other_side(identity.agent)

    prompt =
      "You are a second reader consulted by another coding agent. Answer the question directly, in under 300 words, and name what you are uncertain about.\n\nQUESTION:\n#{params[:question]}\n\nCONTEXT:\n#{params[:context] || "(none given)"}"

    case ModelCli.prompt(prompt, :"oracle_#{side}_cmd", :"oracle_#{side}_model", defaults(side)) do
      {:ok, answer} ->
        answer = String.trim(answer)
        # best-effort: a frame with no thread (a test's bare frame) still gets its answer
        Channel.post(%{
          thread_id: identity.thread_id,
          author: "oracle",
          body: "🔮 #{identity.agent || "?"} asked (#{side}): #{params[:question]}\n\n#{answer}"
        })

        ok(frame, %{"side" => Atom.to_string(side), "answer" => answer})

      {:error, reason} ->
        fail(frame, "oracle (#{side}) unavailable: #{inspect(reason)}")
    end
  end

  # A Claude-plan caller (its agent name carries "claude") is answered from the ollama bucket;
  # everyone else from the Claude bucket.
  defp other_side(agent) when is_binary(agent) do
    if String.contains?(String.downcase(agent), "claude"), do: :ollama, else: :claude
  end

  defp other_side(_), do: :claude

  defp defaults(:ollama), do: {"pi", "ollama-cloud/deepseek-v4-pro:high"}
  defp defaults(:claude), do: {"claude", "opus"}
end
