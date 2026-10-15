defmodule ExBooking.DateWindowTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.DatedOccurrence

  doctest ExBooking.CalendarWindow
  doctest ExBooking.DatedOccurrence

  test "an empty single-day window returns an empty result" do
    assert {:ok, []} =
             ExBooking.date_window([], ~D[2026-10-14], ~D[2026-10-14], [])
  end

  test "inclusive leap-day edges preserve input order and duplicate references" do
    entries = Enum.map([~D[2024-03-01], ~D[2024-02-28], ~D[2024-02-29]], &entry/1)
    assert {:ok, [first, last]} = ExBooking.date_window(entries, ~D[2024-02-29], ~D[2024-03-01])
    assert [first, last] == [Enum.at(entries, 0), Enum.at(entries, 2)]
    assert {:ok, [last]} = ExBooking.date_window(entries, ~D[2024-02-29], ~D[2024-02-29])
    assert {:ok, [last, last]} = ExBooking.date_window([last, last], last.on, last.on)
  end

  test "the optional instant retains another day and precision" do
    occurrence = %DatedOccurrence{
      on: ~D[2026-03-29],
      starts_at: ~U[2026-03-28 23:30:00.123456Z],
      reference: "opaque"
    }

    assert {:ok, [^occurrence]} =
             ExBooking.date_window([occurrence], ~D[2026-03-29], ~D[2026-03-29])

    assert {:ok, []} = ExBooking.date_window([occurrence], ~D[2026-03-28], ~D[2026-03-28])
  end

  test "representable year edges need no successor arithmetic" do
    for date <- [~D[0000-01-01], ~D[9999-12-31]] do
      occurrence = entry(date)
      assert {:ok, [^occurrence]} = ExBooking.date_window([occurrence], date, date)
    end
  end

  test "closed options reject malformed and duplicate values before traversal" do
    for opts <- [
          nil,
          %{},
          [limit: 0],
          [limit: 100_001],
          [limit: 1.0],
          [limit: nil],
          [input_limit: 0],
          [input_limit: 100_001],
          [unknown: 1],
          [limit: 1, limit: 2],
          [:bad],
          [{:limit, 1} | :bad]
        ] do
      assert {:error, {:invalid, :date_window, :options}} =
               ExBooking.date_window(nil, nil, nil, opts)
    end
  end

  test "malformed and reversed date ranges reject before entry validation" do
    valid = ~D[2024-02-29]

    for bad <- [
          nil,
          "2024-02-29",
          %{valid | day: 30},
          %{valid | month: 13},
          %{valid | year: -1},
          %{valid | year: 10_000},
          %{valid | calendar: nil},
          Map.put(valid, :extra, :bad)
        ] do
      assert {:error, {:invalid, :date_window, :range}} = ExBooking.date_window(nil, bad, valid)
      assert {:error, {:invalid, :date_window, :range}} = ExBooking.date_window(nil, valid, bad)
    end

    assert {:error, {:invalid, :date_window, :range}} =
             ExBooking.date_window([], ~D[2024-03-01], valid)
  end

  test "invalid entries outside the window cannot disappear" do
    occurrence = entry(~D[2024-01-01])
    instant = ~U[2024-01-01 00:00:00Z]

    bad_instants = [
      false,
      %{instant | hour: 25},
      %{instant | microsecond: {1_000_000, 6}},
      %{instant | year: 10_000},
      %{instant | utc_offset: 3600},
      %{instant | std_offset: 1},
      %{instant | time_zone: "Europe/Stockholm"},
      %{instant | zone_abbr: "Other"},
      Map.put(instant, :extra, :bad)
    ]

    bad_entries =
      [
        nil,
        %{},
        Map.put(occurrence, :extra, :bad),
        Map.put(Map.delete(occurrence, :on), :extra, nil),
        Map.put(Map.delete(occurrence, :starts_at), :extra, nil),
        Map.put(Map.delete(occurrence, :reference), :extra, nil),
        %{occurrence | on: %{occurrence.on | month: 13}},
        %{occurrence | reference: ""},
        %{occurrence | reference: <<255>>},
        %{occurrence | reference: String.duplicate("a", 257)},
        %{occurrence | reference: :bad}
      ] ++
        Enum.map(bad_instants, &%{occurrence | starts_at: &1})

    for bad <- bad_entries do
      assert {:error, {:invalid, :date_window, :occurrence}} =
               ExBooking.date_window([bad], ~D[2024-02-01], ~D[2024-02-29])
    end
  end

  test "exact limits succeed and excess returns no partial result" do
    occurrence = entry(~D[2024-02-29])
    outside = entry(~D[2024-03-01])
    from = occurrence.on

    assert {:ok, [^occurrence]} =
             ExBooking.date_window([occurrence, outside], from, from, input_limit: 2, limit: 1)

    assert {:error, {:limit, :date_window, :input}} =
             ExBooking.date_window([outside, occurrence], from, from, input_limit: 1)

    assert {:error, {:limit, :date_window, :output}} =
             ExBooking.date_window([occurrence, occurrence], from, from, limit: 1)

    assert {:ok, []} = ExBooking.date_window([], from, from, input_limit: 100_000, limit: 100_000)
  end

  test "non-list and improper-list inputs return closed errors" do
    for input <- [nil, %{}, :bad, [entry(~D[2024-02-29]) | :bad]] do
      assert {:error, {:invalid, :date_window, :occurrences}} =
               ExBooking.date_window(input, ~D[2024-02-29], ~D[2024-02-29])
    end
  end

  test "maximum admitted input and output are exact and remain bounded" do
    occurrence = entry(~D[9999-12-31])
    entries = List.duplicate(occurrence, 100_000)
    opts = [input_limit: 100_000, limit: 100_000]

    assert {:ok, ^entries} = ExBooking.date_window(entries, occurrence.on, occurrence.on, opts)

    assert {:error, {:limit, :date_window, :input}} =
             ExBooking.date_window([occurrence | entries], occurrence.on, occurrence.on, opts)
  end

  test "per-entry error precedence holds after an exact output limit" do
    occurrence = entry(~D[2024-02-29])
    outside = entry(~D[2024-03-01])
    from = occurrence.on

    assert {:error, {:limit, :date_window, :input}} =
             ExBooking.date_window([occurrence, :invalid], from, from, input_limit: 1, limit: 1)

    assert {:error, {:invalid, :date_window, :occurrence}} =
             ExBooking.date_window([occurrence, :invalid], from, from, input_limit: 2, limit: 1)

    assert {:error, {:invalid, :date_window, :occurrences}} =
             ExBooking.date_window([occurrence | :invalid], from, from, input_limit: 1, limit: 1)

    assert {:ok, [^occurrence]} =
             ExBooking.date_window([occurrence, outside], from, from, input_limit: 2, limit: 1)
  end

  test "opaque reference bounds count UTF-8 bytes and preserve the accepted value" do
    reference = String.duplicate("\u00e9", 128)
    occurrence = %{entry(~D[0000-01-01]) | reference: reference}

    assert {:ok, [^occurrence]} =
             ExBooking.date_window([occurrence], occurrence.on, occurrence.on)

    assert {:error, {:invalid, :date_window, :occurrence}} =
             ExBooking.date_window(
               [%{occurrence | reference: reference <> "a"}],
               occurrence.on,
               occurrence.on
             )
  end

  property "selection equals an independent calendar-field oracle without reordering" do
    check all(
            offsets <- list_of(integer(-60..150), max_length: 80),
            lower <- integer(0..3_652_424),
            width <- integer(0..90)
          ) do
      date = fn day ->
        day
        |> :calendar.gregorian_days_to_date()
        |> Date.from_erl!()
      end

      from = date.(lower)
      to = date.(min(lower + width, 3_652_424))
      entries = Enum.map(offsets, &entry(date.(min(max(lower + &1, 0), 3_652_424))))
      coordinates = fn date -> {date.year, date.month, date.day} end

      expected =
        Enum.filter(entries, fn e ->
          coordinates.(e.on) >= coordinates.(from) and coordinates.(e.on) <= coordinates.(to)
        end)

      assert {:ok, ^expected} = ExBooking.date_window(entries, from, to)
    end
  end

  property "adjacent inclusive windows partition the same occurrences" do
    check all(
            offsets <- list_of(integer(0..365), max_length: 80),
            split <- integer(0..364)
          ) do
      first = ~D[2024-01-01]
      last = Date.add(first, 365)
      middle = Date.add(first, split)
      entries = Enum.map(offsets, &entry(Date.add(first, &1)))
      assert {:ok, whole} = ExBooking.date_window(entries, first, last)
      assert {:ok, left} = ExBooking.date_window(entries, first, middle)
      assert {:ok, right} = ExBooking.date_window(entries, Date.add(middle, 1), last)
      assert Enum.sort(left ++ right) == Enum.sort(whole)
    end
  end

  defp entry(date), do: %DatedOccurrence{on: date, reference: "same"}
end
