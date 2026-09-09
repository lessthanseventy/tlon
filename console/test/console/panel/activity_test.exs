defmodule Console.Panel.ActivityTest do
  # The funes activity feed (Tlön right sidebar): one row per buffered `{tag, row}` Bus event,
  # newest-first, colored by `Console.Style`'s semantic event styles. Headless: pins the
  # event → styled-row mapping (`summarize/1`, shared with the footer pulse) without a TTY.
  use ExUnit.Case, async: true

  alias Console.Panel.Activity

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  defp style_of(rows, needle) do
    Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t =~ needle, do: s end) end)
  end

  test "empty buffer renders an empty-state row (title lives on the frame now)" do
    text = %{events: []} |> Activity.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "no activity"
  end

  test "renders an AWAITING YOU gate section above the feed (Slice 4D ATTENTION surfacing)" do
    gates = [%{id: 7, title: "the redis cache", stage: "spec", awaiting: "andrew"}]
    data = %{events: [{:fact_banked, %{id: 1, kind: "x", text: "y"}}], gates: gates}
    text = data |> Activity.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "AWAITING YOU"
    assert text =~ "#7"
    assert text =~ "the redis cache"
    assert text =~ "spec"
    # The gate section leads (attention before ambient feed).
    assert :binary.match(text, "AWAITING") < :binary.match(text, "fact #1")
  end

  test "no gates key → no awaiting section, just the feed (back-compat with the plain shape)" do
    text = %{events: []} |> Activity.render(@rect) |> lines() |> Enum.join("\n")
    refute text =~ "AWAITING"
    assert text =~ "no activity"
  end

  test "renders a fact_banked row and a check_failed row, newest-first, with semantic styles" do
    fact = %{id: 35, kind: "insight", text: "aleph:check is the aleph gate"}
    check_failed = %{kind: "check_failed", detail: %{"cmd" => "mix test", "exit" => 1, "tail" => "1 failure"}}

    data = %{events: [{:fact_banked, fact}, {:event_recorded, check_failed}]}
    rows = Activity.render(data, @rect)
    text = rows |> lines() |> Enum.join("\n")

    assert text =~ "fact #35"
    assert text =~ "insight"
    assert text =~ "aleph:check is the aleph gate"
    assert text =~ "mix test"

    assert style_of(rows, "fact #35") == :event_ok
    assert style_of(rows, "mix test") == :event_bad
  end

  test "summarize/1 maps every activity-topic shape to {icon, style, text}" do
    assert {_, :event_ok, text} =
             Activity.summarize({:event_recorded, %{kind: "check_passed", detail: %{"cmd" => "mix test"}}})

    assert text =~ "mix test"

    assert {_, :event_done, text} =
             Activity.summarize({:event_recorded, %{kind: "work_landed", detail: %{"summary" => "shipped the panel"}}})

    assert text =~ "shipped the panel"

    assert {"▸ ", :event_msg, "claude: hello"} =
             Activity.summarize({:message_posted, %{author: "claude", body: "hello"}})

    assert {"◆ ", :event_warn, text} = Activity.summarize({:issue_raised, %{summary: "flaky test", found_by: "pi"}})
    assert text =~ "flaky test"

    assert {"◆ ", :event_warn, text} = Activity.summarize({:question_raised, %{text: "does raxol support embedding?"}})
    assert text =~ "raxol"
  end

  test "summarize/1 flattens embedded whitespace so a summary is always one clean line" do
    {_, _, text} = Activity.summarize({:message_posted, %{author: "pi", body: "line one\nline two\t tabbed"}})
    refute text =~ "\n"
    refute text =~ "\t"
    assert text == "pi: line one line two tabbed"
  end
end
