defmodule Server.FactTest do
  # `bank_changeset/1` unit tests. §4: `intent` (what a fact is FOR) rides the
  # write path so Cut 3's value gradient has something to grade against; it is
  # optional (not part of validate_required) — a fact can be banked without one.
  use ExUnit.Case, async: true

  alias Server.Fact

  test "bank_changeset casts intent (what the fact was for)" do
    cs =
      Fact.bank_changeset(%{
        kind: "learned",
        text: "x",
        provenance: "derived",
        intent: "why we kept it"
      })

    assert cs.valid?
    assert Ecto.Changeset.get_change(cs, :intent) == "why we kept it"
  end
end
