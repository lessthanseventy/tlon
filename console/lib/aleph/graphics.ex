defmodule Console.Graphics do
  @moduledoc """
  The kitty-graphics seam (design 2026-08-23 §Images): pure APC sequence builders + a placement
  differ, capability-gated. Panels declare image placements `%{id, data, rect}` (raw PNG bytes;
  the read that produced the data owns the file IO); `sync/2` diffs them against the
  transmitted-id cache and returns `{iodata, next_cache}` — transmit once per id, place per
  frame, delete what vanished. The tty write is the caller's; everything here is testable.
  Non-kitty hosts skip sync entirely and render `placeholder/2` runs instead.
  """

  @chunk 4096

  @doc "Is the host kitty (or kitty-graphics capable)? Env detection — cheap, per call."
  @spec kitty?() :: boolean()
  def kitty? do
    System.get_env("KITTY_WINDOW_ID") != nil or String.contains?(System.get_env("TERM") || "", "kitty")
  end

  @doc "A dim placeholder run for hosts without graphics."
  @spec placeholder(pos_integer(), pos_integer()) :: [{String.t(), atom()}]
  def placeholder(w, h), do: [{"[image #{w}x#{h}]", :dim}]

  @doc "Transmit PNG bytes under `id` — chunked base64 APC, `m=1` continuation until the last."
  @spec transmit(non_neg_integer(), binary()) :: [String.t()]
  def transmit(id, png) when is_binary(png) do
    chunks = png |> Base.encode64() |> chunk_every()
    last = length(chunks) - 1

    chunks
    |> Enum.with_index()
    |> Enum.map(fn
      {c, 0} when last == 0 -> "\e_Gf=100,a=t,q=2,i=#{id};#{c}\e\\"
      {c, 0} -> "\e_Gf=100,a=t,q=2,i=#{id},m=1;#{c}\e\\"
      {c, ^last} -> "\e_Gm=0;#{c}\e\\"
      {c, _i} -> "\e_Gm=1;#{c}\e\\"
    end)
  end

  @doc "Place transmitted `id` over a cell rect: save cursor, move, place, restore."
  @spec place(non_neg_integer(), Console.Panel.rect()) :: iodata()
  def place(id, %{x: x, y: y, w: w, h: h}),
    do: ["\e7", "\e[#{y + 1};#{x + 1}H", "\e_Ga=p,q=2,i=#{id},c=#{w},r=#{h}\e\\", "\e8"]

  @doc "Delete every placement of `id` (scroll/close/resize)."
  @spec delete(non_neg_integer()) :: String.t()
  def delete(id), do: "\e_Ga=d,d=i,i=#{id},q=2\e\\"

  @doc "Delete EVERY placement (resize/teardown)."
  @spec delete_all() :: String.t()
  def delete_all, do: "\e_Ga=d,d=a,q=2\e\\"

  @doc """
  Diff wanted placements against the transmitted-id cache → `{iodata_to_write, next_cache}`.
  A deleted id drops OUT of the cache — a re-appearing image re-transmits.
  """
  @spec sync([%{id: non_neg_integer(), data: binary(), rect: map()}], MapSet.t()) :: {iodata(), MapSet.t()}
  def sync(wanted, cache) do
    wanted_ids = MapSet.new(wanted, & &1.id)

    transmits = for p <- wanted, not MapSet.member?(cache, p.id), do: transmit(p.id, p.data)
    places = Enum.map(wanted, &place(&1.id, &1.rect))
    deletes = for id <- MapSet.difference(cache, wanted_ids), do: delete(id)

    {[transmits, places, deletes], wanted_ids}
  end

  defp chunk_every(b64) do
    b64
    |> Stream.unfold(fn
      "" -> nil
      s -> String.split_at(s, @chunk)
    end)
    |> Enum.to_list()
  end
end
