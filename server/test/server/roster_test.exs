defmodule Server.RosterTest do
  # Routing by grade × specialty (roster design §6): a pure ranking over the free seats of a kind.
  use ExUnit.Case, async: true

  alias Server.Coworker
  alias Server.Roster

  defp seat(name, grade, specialty \\ nil, model \\ "m"),
    do: %{coworker: %Coworker{name: name, grade: grade, specialty: specialty}, model: model}

  test "the wanted grade: tertius's word, else greybeard for migrations, gates and the spec, else senior" do
    assert Roster.wanted_grade("tweak the lamp", "junior") == "junior"
    assert Roster.wanted_grade("add a migration for seat grades", nil) == "greybeard"
    assert Roster.wanted_grade("touch priv/repo/migrations", nil) == "greybeard"
    assert Roster.wanted_grade("the nightly gate on main", nil) == "greybeard"
    assert Roster.wanted_grade("rewrite docs/spec.md §5", nil) == "greybeard"
    assert Roster.wanted_grade("a mailbox on the street", nil) == "senior"
  end

  test "the specialty: the one area the ask's paths name, else none" do
    assert Roster.specialty_of("fix office/kit/sim.ts") == "office"
    assert Roster.specialty_of("server/lib/server/staffing.ex races") == "server"
    assert Roster.specialty_of("office/ and server/ both") == nil
    assert Roster.specialty_of("a general chore") == nil
  end

  test "pick: the grade nearest the wanted one, then the specialty, then bench order" do
    seats = [seat("a", "greybeard"), seat("b", "junior", "server"), seat("c", "junior", "office")]
    assert {%{name: "c"}, []} = Roster.pick(seats, %{grade: "junior", specialty: "office"})
    assert {%{name: "a"}, []} = Roster.pick(seats, %{grade: "greybeard"})
    assert {%{name: "b"}, []} = Roster.pick(seats, %{grade: "junior"})
  end

  test "an ungraded seat counts as senior" do
    assert {%{name: "u"}, []} = Roster.pick([seat("j", "junior"), seat("u", nil)], %{grade: "senior"})
  end

  test "a reviewer is never the builder's model, and at least the builder's grade" do
    seats = [
      seat("same", "greybeard", nil, "fable"),
      seat("low", "junior", nil, "haiku"),
      seat("ok", "senior", nil, "opus")
    ]

    assert {%{name: "ok"}, []} = Roster.pick(seats, %{grade: "senior", not_model: "fable", min_grade: "senior"})
  end

  test "when no reviewer qualifies the pick still comes back, with what it falls short of" do
    seats = [seat("same", "senior", nil, "sonnet")]

    assert {%{name: "same"}, [:same_model]} =
             Roster.pick(seats, %{grade: "senior", not_model: "sonnet", min_grade: "senior"})

    assert {%{name: "low"}, [:below_grade]} =
             Roster.pick([seat("low", "junior", nil, "haiku")], %{
               grade: "senior",
               not_model: "sonnet",
               min_grade: "senior"
             })
  end

  test "no seats, no pick" do
    assert Roster.pick([], %{grade: "senior"}) == nil
  end
end
