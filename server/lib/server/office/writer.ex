defmodule Server.Office.Writer do
  @moduledoc """
  Who writes the office's flavour text — the pets' lines and exchanges (`Server.Office.Pets`), the
  crew's small talk (`Server.Office.Banter`) and their corkboard notes (`Server.Office.Corkboard`) —
  and in what mood.

  The model follows the workspace's shift (`Server.Shifts`), so the flavour text drains the bucket
  that is already draining: on the day shift (the Claude crew) mostly Haiku, now and then deepseek;
  on the night shift (the pi crew, which a Claude usage limit switches on) only the ollama models,
  deepseek and kimi. A Haiku call that fails falls back to deepseek. Each call also draws a
  FLAVOUR, one line on the prompt, so one batch differs from the next in kind, not only in wording.

  How wild all of it is follows the operator's `wackiness` knob — the voice half of the toy design's
  dial (business → rimworld): 0 business writes nothing (the office falls back to its few canned
  lines), 1 business casual is wry and warm, 2 office party is bits and running gags, 3 rimworld is
  moods that swing on what actually happened, grudges remembered and everything escalating.

  `config :server, banter_cmd:` (a test's stand-in CLI) pins every call to it instead.
  """

  @deepseek {"pi", "ollama-cloud/deepseek-v4.1-flash"}
  @pools %{
    "day" => [{"claude", "haiku"}, {"claude", "haiku"}, @deepseek],
    "night" => [@deepseek, @deepseek, {"pi", "ollama-cloud/kimi-k2.7-code"}]
  }
  @flavours [
    "deadpan and dry: understatement, a straight face",
    "absurd: one surreal tangent that follows its own logic",
    "gossip: about the people in the office, by name, affectionate",
    "theatrical: everything is an epic, a tragedy or a triumph",
    "petty grievances: small injustices taken very seriously",
    "Borgesian: labyrinths, mirrors, infinite libraries, forgotten books",
    "wordplay: puns and double meanings, groan-worthy is fine",
    "wistful: a little nostalgic about something that happened today",
    "conspiratorial: whispered theories about the machine and its moods",
    "sports commentary: the work narrated like a close match"
  ]

  @tones %{
    1 => "business casual: personality, lightly — wry and warm, about today",
    2 => "office party: loud and silly — bits, running gags, inside jokes; nobody is entirely sensible",
    3 =>
      "RIMWORLD: moods swing on what actually happened today (a red build sours someone for the afternoon, " <>
        "a merge makes someone insufferable), rivalries and grudges flare and are remembered, everything " <>
        "escalates and catastrophizes; the drama is the point, but never cruel"
  }

  @doc "How wild the office's voices are: the `wackiness` knob's tone line, or nil at 0 (business)."
  def tone, do: @tones[Server.OperatorConfig.setting("wackiness")]

  @doc "The models the workspace's shift draws from, `[{cmd, model}]`, a likelier one listed more often."
  def pool(workspace_id), do: Map.get(@pools, Server.Shifts.current(workspace_id), @pools["night"])

  @doc "The flavours a call may draw."
  def flavours, do: @flavours

  @doc """
  Write `prompt` for workspace `workspace_id`: a model from its shift's pool, a flavour on the
  prompt. `{:ok, stdout}` or `Server.ModelCli`'s `{:error, _}`.
  """
  def write(prompt, workspace_id) do
    cond do
      Application.get_env(:server, :banter_cmd) -> Server.ModelCli.prompt(prompt, :banter_cmd, :banter_model, @deepseek)
      tone() == nil -> {:error, :business}
      true -> drawn(prompt, workspace_id)
    end
  end

  defp drawn(prompt, workspace_id) do
    {cmd, model} = Enum.random(pool(workspace_id))
    ask = prompt <> "\nHOW WILD — #{tone()}.\nTHIS TIME'S FLAVOUR — #{Enum.random(@flavours)}. Lean into it."

    case Server.ModelCli.run(ask, cmd, model) do
      {:error, _} when cmd == "claude" -> Server.ModelCli.run(ask, elem(@deepseek, 0), elem(@deepseek, 1))
      result -> result
    end
  end
end
