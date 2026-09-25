defmodule Server.LeafWindow do
  @moduledoc """
  Human window names for leaf sessions (per-thread-agents Slice C). A leaf's tmux window is named
  `<archetype>-<title-slug>` — readable in the window bar and `tmux list-windows` — instead of the
  routing id `t<id>`. The name is COSMETIC: routing rides the `@funes_thread` window option the
  cockpit stamps at spawn (`thread_id → window`, never name parsing), so collisions only cost a
  `-2` disambiguator, not a misdelivery.
  """

  # Slug budget: long enough to read the subject, short enough for a tab strip of several leaves.
  @max_slug 24

  @doc """
  The window name for a leaf: `<archetype>-<slug>`, the slug truncated to ~#{@max_slug} chars on a
  word boundary where possible. `taken` (existing window names) adds a `-2`/`-3`… disambiguator
  only on collision. A blank/unsluggable title falls back to the bare archetype.

      iex> Server.LeafWindow.name(:reviewer, "let's review this PR")
      "reviewer-let-s-review-this-pr"

      iex> Server.LeafWindow.name(:builder, "implement the per-thread agents design end to end")
      "builder-implement-the-per-thread"

      iex> Server.LeafWindow.name(:planner, "???")
      "planner"

      iex> Server.LeafWindow.name(:reviewer, "review", ["reviewer-review", "reviewer-review-2"])
      "reviewer-review-3"
  """
  @spec name(atom() | String.t(), String.t() | nil, [String.t()]) :: String.t()
  def name(archetype, title, taken \\ []) do
    base =
      case slug(title) do
        "" -> "#{archetype}"
        slug -> "#{archetype}-#{slug}"
      end

    disambiguate(base, MapSet.new(taken), 2)
  end

  @doc "Lowercase, non-alphanumerics collapsed to `-`, truncated to #{@max_slug} chars (word-boundary preferred)."
  @spec slug(String.t() | nil) :: String.t()
  def slug(nil), do: ""

  def slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> truncate()
  end

  defp truncate(slug) when byte_size(slug) <= @max_slug, do: slug

  defp truncate(slug) do
    cut = binary_part(slug, 0, @max_slug)

    cond do
      # The cut landed exactly on a word boundary — the cut is whole words already.
      binary_part(slug, @max_slug, 1) == "-" -> cut
      # Drop the trailing cut-off word — unless that leaves nothing.
      not String.contains?(cut, "-") -> cut
      true -> cut |> String.split("-") |> Enum.drop(-1) |> Enum.join("-")
    end
  end

  defp disambiguate(base, taken, n) do
    cond do
      base not in taken -> base
      "#{base}-#{n}" not in taken -> "#{base}-#{n}"
      true -> disambiguate(base, taken, n + 1)
    end
  end
end
