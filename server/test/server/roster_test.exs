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

  describe "the trust record tie-break" do
    defp trusted(seat, led, first_time), do: Map.put(seat, :trust, %{led: led, first_time: first_time})

    test "between otherwise equal seats the better first-time-landing record wins" do
      seats = [trusted(seat("a", "senior"), 10, 5), trusted(seat("b", "senior"), 10, 9)]
      assert {%{name: "b"}, []} = Roster.pick(seats, %{grade: "senior"})
    end

    test "a record never overrides a grade or specialty mismatch" do
      seats = [
        trusted(seat("good", "junior", "server"), 10, 10),
        trusted(seat("fit", "senior", "office"), 10, 1)
      ]

      assert {%{name: "fit"}, []} = Roster.pick(seats, %{grade: "senior", specialty: "office"})
      assert {%{name: "fit"}, []} = Roster.pick(seats, %{grade: "senior"})
    end

    test "a record never overrides the builder's-model rule" do
      seats = [trusted(seat("same", "senior", nil, "fable"), 10, 10), seat("other", "senior", nil, "opus")]
      assert {%{name: "other"}, []} = Roster.pick(seats, %{grade: "senior", not_model: "fable"})
    end

    test "no record is neutral: above a poor record, below a good one, never the worst" do
      none = seat("none", "senior")
      assert {%{name: "none"}, []} = Roster.pick([trusted(seat("poor", "senior"), 10, 2), none], %{grade: "senior"})
      assert {%{name: "good"}, []} = Roster.pick([none, trusted(seat("good", "senior"), 10, 9)], %{grade: "senior"})
      assert {%{name: "none"}, []} = Roster.pick([none, trusted(seat("zero", "senior"), 0, 0)], %{grade: "senior"})
    end

    test "equal records fall back to bench order" do
      seats = [trusted(seat("a", "senior"), 10, 5), trusted(seat("b", "senior"), 10, 5)]
      assert {%{name: "a"}, []} = Roster.pick(seats, %{grade: "senior"})
    end
  end
end
