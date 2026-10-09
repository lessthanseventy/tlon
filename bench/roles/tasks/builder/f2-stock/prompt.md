Bug report from the shop: "when a customer cancels an order, the mugs it held never come back — the
shelf says 3 available but there are 5 mugs sitting there. And after we ship an order, the shelf count
drops twice: we shipped 2 of 5 mugs and it says only 1 can be sold."

The stock code is `lib/stock.ex`. Find what causes both symptoms, fix them test-first, and commit.
The repo is plain Elixir scripts, no Mix project: `elixir test/stock_test.exs` runs its tests.
