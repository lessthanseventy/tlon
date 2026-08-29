defmodule Console.MachineChat.Layout do
  @moduledoc """
  The machine-chat screen's geometry — pure `{w, h} → rects`, Slack-shaped: a one-row header,
  a left THREADS rail, the center conversation, a right CREW rail, and a 3-row composer under
  the center. Rails collapse on narrow terminals (crew first, then threads) so the conversation
  always wins the space. Separator columns are 1-wide rects the loop paints `│` into.
  """

  @rail_w 26
  @crew_w 26
  # Show the threads rail from this width; the crew rail from this one.
  @rail_min_w 80
  @crew_min_w 118
  @composer_h 3
  @header_h 1

  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), w: pos_integer(), h: pos_integer()}

  @doc """
  All the screen's rects. `rail`/`crew` (and their separators) are nil when collapsed.
  `composer_content` grows the compose box (spacer + rule + that many input lines),
  capped at half the body so the conversation always survives.
  """
  @spec compute(pos_integer(), pos_integer(), pos_integer()) :: %{
          header: rect(),
          rail: rect() | nil,
          rail_sep: rect() | nil,
          center: rect(),
          crew: rect() | nil,
          crew_sep: rect() | nil,
          composer: rect()
        }
  def compute(w, h, composer_content \\ 1) do
    w = max(w, 20)
    h = max(h, @header_h + @composer_h + 1)
    composer_h = 2 + (composer_content |> max(1) |> min(content_cap(h)))
    body_y = @header_h
    body_h = h - @header_h - composer_h

    rail? = w >= @rail_min_w
    crew? = w >= @crew_min_w

    rail_w = if rail?, do: @rail_w, else: 0
    crew_w = if crew?, do: @crew_w, else: 0
    center_x = if rail?, do: rail_w + 1, else: 0
    center_w = w - center_x - if crew?, do: crew_w + 1, else: 0

    %{
      header: %{x: 0, y: 0, w: w, h: @header_h},
      rail: if(rail?, do: %{x: 0, y: body_y, w: rail_w, h: body_h}),
      rail_sep: if(rail?, do: %{x: rail_w, y: body_y, w: 1, h: body_h}),
      center: %{x: center_x, y: body_y, w: max(center_w, 1), h: body_h},
      crew: if(crew?, do: %{x: w - crew_w, y: body_y, w: crew_w, h: body_h}),
      crew_sep: if(crew?, do: %{x: w - crew_w - 1, y: body_y, w: 1, h: body_h}),
      composer: %{x: center_x, y: body_y + body_h, w: max(center_w, 1), h: composer_h}
    }
  end

  # Half the space below the header, less the box's spacer + rule — never starves the center.
  defp content_cap(h), do: max(div(h - @header_h - 2, 2), 1)
end
