defmodule Server.Roster do
  @moduledoc """
  Who should take a piece of work, among the free seats of the kind it needs (roster design §6):
  the grade it wants, the area it touches, and for a review, a model other than the builder's at
  no lower a grade. Pure — the caller hands in the candidates with their resolved models.

  The grade a piece of work wants is the manager's word when it gave one (`staff_child`'s
  `grade`); else greybeard for migrations, gates and the spec; else senior.
  """

  @ranks %{"junior" => 1, "senior" => 2, "greybeard" => 3}
  @greybeard ~r/migration|priv\/repo\/migrations|\bgate\b|spec\.md|\bthe spec\b/i

  @doc "The grade an ask wants: `explicit` when given, else from what it names."
  @spec wanted_grade(String.t() | nil, String.t() | nil) :: String.t()
  def wanted_grade(_text, explicit) when is_binary(explicit), do: explicit
  def wanted_grade(text, nil), do: if(Regex.match?(@greybeard, text || ""), do: "greybeard", else: "senior")

  @doc "The one area (`office`, `server`) an ask's paths name, else nil."
  @spec specialty_of(String.t() | nil) :: String.t() | nil
  def specialty_of(text) do
    case Enum.filter(["office", "server"], &String.contains?(text || "", &1 <> "/")) do
      [one] -> one
      _ -> nil
    end
  end

  @doc """
  The best of `candidates` (`%{coworker, model}`) for `want` (`grade`, and optionally `specialty`,
  `not_model`, `min_grade`): `{coworker, shortfalls}`, the shortfalls `:same_model` and
  `:below_grade` naming what no candidate could meet; nil for none.
  """
  @spec pick([%{coworker: Server.Coworker.t(), model: String.t() | nil}], map()) ::
          {Server.Coworker.t(), [:same_model | :below_grade]} | nil
  def pick([], _want), do: nil

  def pick(candidates, want) do
    %{coworker: c} =
      best =
      candidates
      |> Enum.with_index()
      |> Enum.min_by(fn {cand, i} ->
        {same_model?(cand, want), below?(cand, want), distance(cand, want), miss?(cand, want), i}
      end)
      |> elem(0)

    {c,
     [same_model: same_model?(best, want), below_grade: below?(best, want)]
     |> Enum.filter(&elem(&1, 1))
     |> Keyword.keys()}
  end

  defp rank(grade), do: Map.get(@ranks, grade, @ranks["senior"])

  defp same_model?(%{model: m}, %{not_model: m}) when not is_nil(m), do: true
  defp same_model?(_cand, _want), do: false

  defp below?(%{coworker: c}, %{min_grade: g}) when is_binary(g), do: rank(c.grade) < rank(g)
  defp below?(_cand, _want), do: false

  defp distance(%{coworker: c}, want), do: abs(rank(c.grade) - rank(want[:grade]))

  defp miss?(%{coworker: %{specialty: s}}, %{specialty: want}) when is_binary(want), do: s != want
  defp miss?(_cand, _want), do: false
end
