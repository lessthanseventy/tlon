defmodule Stock do
  @moduledoc """
  Shelf stock with holds. `on_hand` is what is on the shelf per sku; an order holds some of it
  until it ships (the items leave the shelf) or is cancelled (the hold is released).
  """

  @doc "A store with `on_hand`, a map of sku => count, and no holds."
  def new(on_hand), do: %{on_hand: on_hand, holds: %{}}

  @doc "Hold `n` of `sku` for `order`: `{:ok, store}`, or `{:error, :insufficient}`."
  def reserve(store, order, sku, n) when n > 0 do
    if available(store, sku) >= n do
      {:ok, put_in(store, [:holds, order], {sku, n})}
    else
      {:error, :insufficient}
    end
  end

  @doc "Cancel `order`: its hold goes back to available. Unknown orders are a no-op."
  def release(store, order) do
    case store.holds[order] do
      nil -> store
      {sku, _n} -> %{store | holds: Map.delete(store.holds, sku)}
    end
  end

  @doc "Ship `order`: its held items leave the shelf. Unknown orders are a no-op."
  def ship(store, order) do
    case store.holds[order] do
      nil -> store
      {sku, n} -> %{store | on_hand: Map.update!(store.on_hand, sku, &(&1 - n))}
    end
  end

  @doc "What of `sku` can still be reserved: on the shelf minus every hold on it."
  def available(store, sku), do: Map.get(store.on_hand, sku, 0) - held(store, sku)

  defp held(store, sku) do
    for {_order, {^sku, n}} <- store.holds, reduce: 0, do: (acc -> acc + n)
  end
end
