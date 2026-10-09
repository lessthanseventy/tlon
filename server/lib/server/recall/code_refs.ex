defmodule Server.Recall.CodeRefs do
  @moduledoc """
  The code symbols a fact's text names, as a pure function of the text — nothing is stored, so a
  rule change applies to every fact on the next sweep. Refs are `{:module, name}`,
  `{:function, name}`, `{:path, path}` and `{:task, name}`. A fact that asserts an absence yields
  none: a passing probe would boost a claim the code now contradicts.
  """

  @module ~r/\bServer(?:\.[A-Z][A-Za-z0-9]*)+/
  @function ~r/\b[A-Z][\w.]*\.([a-z_][\w?!]*)\/\d+/
  @path ~r/\b(?:server|office|adapters|tasks|docs|scripts)\/[\w.\/-]+\.\w+/
  @task ~r/mise run ([\w:-]+)/
  @absence ~r/\b(no caller|does not exist|doesn't exist|never|missing|without|absent|not exist)\b/i

  @spec extract(String.t()) :: [{:module | :function | :path | :task, String.t()}]
  def extract(text) do
    if Regex.match?(@absence, text) do
      []
    else
      Enum.uniq(
        Enum.map(Regex.scan(@module, text), fn [m] -> {:module, m} end) ++
          Enum.map(Regex.scan(@function, text), fn [_, f] -> {:function, f} end) ++
          Enum.map(Regex.scan(@path, text), fn [p] -> {:path, String.trim_trailing(p, ".")} end) ++
          Enum.map(Regex.scan(@task, text), fn [_, t] -> {:task, t} end)
      )
    end
  end
end
