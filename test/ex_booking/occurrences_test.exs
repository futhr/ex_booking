defmodule ExBooking.OccurrencesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.Occurrence
  alias ExBooking.OccurrenceCursor
  alias ExBooking.OccurrencePage
  alias ExBooking.RRule

  doctest Occurrence
  doctest OccurrenceCursor
  doctest OccurrencePage

  @start ~U[2026-07-13 06:00:00Z]

  defmodule ReversingDatabase do
    @moduledoc false

    @spec time_zone_periods_from_wall_datetime(NaiveDateTime.t(), String.t()) :: {:ok, map()}
    def time_zone_periods_from_wall_datetime(wall, "Test/Reverse") do
      offset = if wall.day == 13, do: 0, else: 86_400
      {:ok, %{utc_offset: offset, std_offset: 0, zone_abbr: "TEST"}}
    end

    @spec time_zone_period_from_utc_iso_days(Calendar.iso_days(), String.t()) :: {:ok, map()}
    def time_zone_period_from_utc_iso_days(_, "Test/Reverse") do
      {:ok, %{utc_offset: 0, std_offset: 0, zone_abbr: "TEST"}}
    end
  end

  test "returns original starts instead of clipped availability" do
    opts = utc_opts(from: ~U[2026-07-13 06:05:00Z])
    assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;COUNT=2", @start, opts)
    assert Enum.map(page.occurrences, & &1.starts_at) == [~U[2026-07-14 06:00:00Z]]
    assert Enum.map(page.occurrences, & &1.ordinal) == [2]
    assert hd(page.occurrences).nominal == ~N[2026-07-14 06:00:00]

    assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;COUNT=1", @start, utc_opts())
    assert [%Occurrence{starts_at: @start, ordinal: 1, resolution: :unique}] = page.occurrences

    assert {:ok, intervals} =
             ExBooking.expand_rrule(
               "FREQ=DAILY;COUNT=1",
               @start,
               30,
               Keyword.take(opts, [:from, :until])
             )

    assert hd(intervals).start_at == opts[:from]
  end

  test "COUNT is global, UNTIL inclusive and query until exclusive" do
    opts = utc_opts(from: ~U[2026-07-14 00:00:00Z])
    assert {:ok, %{occurrences: []}} = ExBooking.occurrences("FREQ=DAILY;COUNT=1", @start, opts)
    assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;UNTIL=20260714T060000Z", @start, opts)
    assert Enum.map(page.occurrences, & &1.ordinal) == [2]
    opts = Keyword.put(opts, :until, ~U[2026-07-14 06:00:00Z])
    assert {:ok, %{occurrences: []}} = ExBooking.occurrences("FREQ=DAILY", @start, opts)
  end

  test "pages have stable originals, including an empty final continuation" do
    opts = utc_opts(limit: 1, until: ~U[2026-07-15 00:00:00Z])
    assert {:ok, first} = ExBooking.occurrences("FREQ=DAILY", @start, opts)
    assert %OccurrenceCursor{next_offset_days: 1, emitted_count: 1} = first.next_cursor

    assert {:ok, second} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               @start,
               Keyword.put(opts, :cursor, first.next_cursor)
             )

    assert [%{ordinal: 2}] = second.occurrences

    assert {:ok, final} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               @start,
               Keyword.put(opts, :cursor, second.next_cursor)
             )

    assert %OccurrencePage{occurrences: [], next_cursor: nil} = final

    assert {:ok, whole} =
             ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(opts, :limit, 20))

    assert first.occurrences ++ second.occurrences == whole.occurrences
  end

  test "cursor basis rejects semantic changes but permits changed page/work limits" do
    opts = utc_opts(limit: 1)
    assert {:ok, first} = ExBooking.occurrences("FREQ=DAILY", @start, opts)
    cursor_opts = Keyword.put(opts, :cursor, first.next_cursor)

    for {key, value} <- [
          {:time_zone_basis, "utc-v2"},
          {:from, ~U[2026-07-13 01:00:00Z]},
          {:until, ~U[2026-07-17 00:00:00Z]}
        ] do
      assert {:error, {:stale, :occurrences, :cursor_basis}} =
               ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(cursor_opts, key, value))
    end

    assert {:error, {:stale, :occurrences, :cursor_basis}} =
             ExBooking.occurrences("FREQ=DAILY;INTERVAL=2", @start, cursor_opts)

    assert {:ok, %{occurrences: [%{ordinal: 2}, %{ordinal: 3}]}} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               @start,
               Keyword.merge(cursor_opts, limit: 20, work_limit: 10)
             )
  end

  test "incorrect cursor prefix and noncandidate position reject without partial success" do
    opts = utc_opts(limit: 1)
    assert {:ok, first} = ExBooking.occurrences("FREQ=DAILY", @start, opts)
    original = first.next_cursor

    for cursor <- [
          %{original | emitted_count: 8},
          %{original | next_offset_days: 100},
          %{original | next_offset_days: -1},
          %{original | emitted_count: 1.0},
          Map.put(original, :extra, true),
          Map.delete(original, :basis),
          %{},
          :invalid
        ] do
      assert {:error, {:invalid, :occurrences, :cursor}} =
               ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(opts, :cursor, cursor))
    end

    weekly = utc_opts(limit: 1, until: ~U[2026-08-13 00:00:00Z])
    assert {:ok, page} = ExBooking.occurrences("FREQ=WEEKLY", @start, weekly)
    cursor = %{page.next_cursor | next_offset_days: 1}

    assert {:error, {:invalid, :occurrences, :cursor}} =
             ExBooking.occurrences("FREQ=WEEKLY", @start, Keyword.put(weekly, :cursor, cursor))

    # A pure cursor validates a coordinate, not issuance or consumer processing.
    coherent = %{original | next_offset_days: 2, emitted_count: 2}

    assert {:ok, %{occurrences: [%{ordinal: 3}]}} =
             ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(opts, :cursor, coherent))
  end

  test "work bounds include skipped prefix and cursor verification" do
    opts = utc_opts(work_limit: 2)

    assert {:ok, %{occurrences: [_, _], next_cursor: nil}} =
             ExBooking.occurrences("FREQ=DAILY;COUNT=2", @start, opts)

    assert {:error, {:limit, :occurrences, :work}} =
             ExBooking.occurrences("FREQ=DAILY;COUNT=3", @start, opts)

    assert {:ok, page} =
             ExBooking.occurrences("FREQ=DAILY", @start, utc_opts(limit: 1, work_limit: 1))

    opts = utc_opts(limit: 1, work_limit: 1, cursor: page.next_cursor)

    assert {:error, {:limit, :occurrences, :work}} =
             ExBooking.occurrences("FREQ=DAILY", @start, opts)

    assert {:ok, %{occurrences: [%{ordinal: 2}]}} =
             ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(opts, :work_limit, 2))

    ancient = ~U[1900-01-01 06:00:00Z]

    assert {:error, {:limit, :occurrences, :work}} =
             ExBooking.occurrences("FREQ=DAILY", ancient, utc_opts(work_limit: 2))
  end

  test "sparse, past and year-end horizons terminate without date overflow" do
    for rule <- [
          "FREQ=DAILY;INTERVAL=10000000000000000000",
          "FREQ=WEEKLY;INTERVAL=10000000000000000000;BYDAY=TU"
        ] do
      assert {:ok, _} = ExBooking.occurrences(rule, @start, utc_opts(work_limit: 1))
    end

    assert {:ok, %{occurrences: []}} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               ~U[2030-01-01 06:00:00Z],
               utc_opts(work_limit: 1)
             )

    opts = utc_opts(from: ~U[9999-12-31 00:00:00Z], until: ~U[9999-12-31 23:59:59Z])

    assert {:ok, %{occurrences: [%{ordinal: 1}], next_cursor: nil}} =
             ExBooking.occurrences("FREQ=DAILY", ~U[9999-12-31 06:00:00Z], opts)
  end

  test "explicit database is used regardless of ambient default" do
    start = DateTime.from_naive!(~N[2026-07-13 06:00:00], "Europe/Stockholm", Tz.TimeZoneDatabase)
    opts = zone_opts(start, ~U[2026-07-15 00:00:00Z])
    assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;COUNT=1", start, opts)
    assert hd(page.occurrences).starts_at == ~U[2026-07-13 04:00:00Z]

    assert {:error, {:invalid, :occurrences, :dtstart}} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               start,
               Keyword.put(opts, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)
             )

    assert {:error, {:invalid, :occurrences, :dtstart}} =
             ExBooking.occurrences("FREQ=DAILY", %{start | utc_offset: 0}, opts)
  end

  test "Stockholm and New York gaps do not consume COUNT or ordinals" do
    for {zone, nominal, expected} <- [
          {"Europe/Stockholm", ~N[2026-03-28 02:30:00],
           [~U[2026-03-28 01:30:00Z], ~U[2026-03-30 00:30:00Z]]},
          {"America/New_York", ~N[2026-03-07 02:30:00],
           [~U[2026-03-07 07:30:00Z], ~U[2026-03-09 06:30:00Z]]}
        ] do
      start = DateTime.from_naive!(nominal, zone, Tz.TimeZoneDatabase)
      opts = zone_opts(start, DateTime.add(start, 4, :day))
      assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;COUNT=2", start, opts)
      assert Enum.map(page.occurrences, & &1.starts_at) == expected
      assert Enum.map(page.occurrences, & &1.ordinal) == [1, 2]

      assert {:error, {:limit, :occurrences, :work}} =
               ExBooking.occurrences(
                 "FREQ=DAILY;COUNT=2",
                 start,
                 Keyword.put(opts, :work_limit, 2)
               )

      assert collect_pages("FREQ=DAILY;COUNT=2", start, Keyword.put(opts, :limit, 1)) ==
               page.occurrences
    end
  end

  test "later folds choose first once; a second-fold DTSTART retains its instant" do
    for {zone, nominal} <- [
          {"Europe/Stockholm", ~N[2026-10-25 02:30:00]},
          {"America/New_York", ~N[2026-11-01 01:30:00]}
        ] do
      assert {:ambiguous, first, second} = DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase)
      start = DateTime.add(first, -1, :day)
      opts = zone_opts(start, DateTime.add(second, 2, :day))
      assert {:ok, page} = ExBooking.occurrences("FREQ=DAILY;COUNT=2", start, opts)
      assert List.last(page.occurrences).starts_at == DateTime.shift_zone!(first, "Etc/UTC")
      assert List.last(page.occurrences).resolution == :first_fold
      assert {:ok, second_page} = ExBooking.occurrences("FREQ=DAILY;COUNT=1", second, opts)
      assert hd(second_page.occurrences).starts_at == DateTime.shift_zone!(second, "Etc/UTC")
      assert hd(second_page.occurrences).resolution == :second_fold
    end
  end

  test "fractional instants are preserved, including exact horizon boundaries" do
    start = ~U[2026-07-13 06:00:00.123456Z]
    opts = utc_opts(from: start, until: ~U[2026-07-14 06:00:00.123456Z])
    assert {:ok, %{occurrences: [occurrence]}} = ExBooking.occurrences("FREQ=DAILY", start, opts)
    assert occurrence.starts_at == start
    assert occurrence.nominal == ~N[2026-07-13 06:00:00.123456]

    assert {:ok, %{occurrences: []}} =
             ExBooking.occurrences(
               "FREQ=DAILY",
               start,
               Keyword.put(opts, :from, DateTime.add(start, 1, :microsecond))
             )
  end

  test "non-increasing database resolution is rejected" do
    start = %{@start | time_zone: "Test/Reverse", zone_abbr: "TEST"}
    opts = utc_opts(time_zone_database: ReversingDatabase)

    assert {:error, {:invalid, :occurrences, :time_zone_order}} =
             ExBooking.occurrences("FREQ=DAILY;COUNT=2", start, opts)
  end

  test "malformed options and temporal/native inputs return typed errors" do
    for opts <- [:bad, %{}, [123], [{:from, @start}, {:from, @start}]] do
      assert {:error, {:invalid, :occurrences, :options}} =
               ExBooking.occurrences("FREQ=DAILY", @start, opts)
    end

    for {key, value, reason} <- [
          {:unknown, true, :options},
          {:limit, 0, :limit},
          {:limit, 1025, :limit},
          {:limit, 1.5, :limit},
          {:work_limit, 0, :work_limit},
          {:work_limit, 100_001, :work_limit},
          {:work_limit, 1.0, :work_limit},
          {:time_zone_basis, "", :time_zone_basis},
          {:time_zone_basis, <<255>>, :time_zone_basis},
          {:time_zone_basis, String.duplicate("x", 257), :time_zone_basis},
          {:time_zone_database, ExBooking, :time_zone_database},
          {:time_zone_database, nil, :time_zone_database},
          {:from, nil, :arguments},
          {:until, @start, :arguments}
        ] do
      assert {:error, {:invalid, :occurrences, ^reason}} =
               ExBooking.occurrences("FREQ=DAILY", @start, Keyword.put(utc_opts(), key, value))
    end

    for start <- [
          nil,
          %{@start | month: 13},
          %{@start | year: 10_000},
          %{@start | microsecond: {1, 9}},
          %{@start | utc_offset: 100_000},
          Map.delete(@start, :hour)
        ] do
      assert {:error, {:invalid, :occurrences, :arguments}} =
               ExBooking.occurrences("FREQ=DAILY", start, utc_opts())
    end

    for rule <- [
          :bad,
          Map.delete(%RRule{freq: :daily}, :interval),
          Map.put(%RRule{freq: :daily}, :extra, true),
          %RRule{freq: :weekly, byday: List.duplicate(1, 8)}
        ] do
      assert {:error, {:invalid, :occurrences, :arguments}} =
               ExBooking.occurrences(rule, @start, utc_opts())
    end

    assert {:error, {:invalid, :rrule, :interval}} =
             ExBooking.occurrences(%RRule{freq: :daily, interval: 0}, @start, utc_opts())

    zoned_until =
      DateTime.from_naive!(~N[2026-07-15 06:00:00], "Europe/Stockholm", Tz.TimeZoneDatabase)

    assert {:error, {:invalid, :occurrences, :arguments}} =
             ExBooking.occurrences(%RRule{freq: :daily, until: zoned_until}, @start, utc_opts())

    assert {:error, {:invalid, :rrule, :count_and_until}} =
             ExBooking.occurrences(
               "FREQ=DAILY;COUNT=2;UNTIL=20260715T060000Z",
               @start,
               utc_opts()
             )

    assert {:error, {:unsupported, :rrule, "BYSETPOS"}} =
             ExBooking.occurrences("FREQ=DAILY;BYSETPOS=1", @start, utc_opts())

    for oversized <- [String.duplicate("X", 4097), <<255>>] do
      assert {:error, {:invalid, :occurrences, :rule_size}} =
               ExBooking.occurrences(oversized, @start, utc_opts())
    end
  end

  property "weekly originals match an independent day-by-day calendar reference" do
    check all(
            interval <- integer(1..4),
            weekdays <- list_of(integer(1..7), min_length: 1, max_length: 7),
            count <- integer(1..12),
            {zone, nominal} <-
              member_of([
                {"Europe/Stockholm", ~N[2026-03-25 02:30:00]},
                {"America/New_York", ~N[2026-03-04 02:30:00]},
                {"Europe/Stockholm", ~N[2026-10-21 02:30:00]},
                {"America/New_York", ~N[2026-10-28 01:30:00]}
              ])
          ) do
      start = DateTime.from_naive!(nominal, zone, Tz.TimeZoneDatabase)
      until = DateTime.add(start, 100, :day)
      rule = %RRule{freq: :weekly, interval: interval, byday: weekdays, count: count}
      opts = zone_opts(start, until)
      assert {:ok, actual} = ExBooking.occurrences(rule, start, opts)
      expected = reference_weekly(rule, start, until)
      assert expected != []
      assert Enum.map(actual.occurrences, &{&1.starts_at, &1.ordinal}) == expected
      assert collect_pages(rule, start, Keyword.put(opts, :limit, 3)) == actual.occurrences
    end
  end

  property "pagination and narrower horizons never change original occurrence coordinates" do
    check all(
            count <- integer(2..30),
            lower <- integer(0..(count - 1)),
            limit <- integer(1..8)
          ) do
      until = DateTime.add(@start, count + 1, :day)
      opts = utc_opts(until: until)
      rule = "FREQ=DAILY;COUNT=#{count}"
      assert {:ok, whole} = ExBooking.occurrences(rule, @start, opts)
      narrow = Keyword.put(opts, :from, DateTime.add(@start, lower, :day))
      assert {:ok, page} = ExBooking.occurrences(rule, @start, narrow)
      assert page.occurrences == Enum.drop(whole.occurrences, lower)
      assert page.occurrences != []
      assert collect_pages(rule, @start, Keyword.put(narrow, :limit, limit)) == page.occurrences
    end
  end

  defp utc_opts(overrides \\ []) do
    Keyword.merge(
      [
        from: ~U[2026-07-13 06:00:00Z],
        until: ~U[2026-07-16 00:00:00Z],
        time_zone_database: Calendar.UTCOnlyTimeZoneDatabase,
        time_zone_basis: "utc-v1"
      ],
      overrides
    )
  end

  defp zone_opts(start, until) do
    [
      from: DateTime.shift_zone!(start, "Etc/UTC"),
      until: DateTime.shift_zone!(until, "Etc/UTC"),
      time_zone_database: Tz.TimeZoneDatabase,
      time_zone_basis: "test-tz-basis"
    ]
  end

  defp collect_pages(rule, start, opts, acc \\ []) do
    assert {:ok, page} = ExBooking.occurrences(rule, start, opts)
    acc = acc ++ page.occurrences

    if page.next_cursor,
      do: collect_pages(rule, start, Keyword.put(opts, :cursor, page.next_cursor), acc),
      else: acc
  end

  defp reference_weekly(rule, start, until) do
    date = DateTime.to_date(start)
    monday = Date.add(date, 1 - Date.day_of_week(date))

    0..100
    |> Enum.map(&Date.add(date, &1))
    |> Enum.filter(fn candidate ->
      week = div(Date.diff(candidate, monday), 7)
      rem(week, rule.interval) == 0 and Date.day_of_week(candidate) in rule.byday
    end)
    |> Enum.flat_map(fn candidate ->
      nominal = NaiveDateTime.new!(candidate, DateTime.to_time(start))

      case DateTime.from_naive(nominal, start.time_zone, Tz.TimeZoneDatabase) do
        {:ok, dt} -> [DateTime.shift_zone!(dt, "Etc/UTC")]
        {:ambiguous, first, _} -> [DateTime.shift_zone!(first, "Etc/UTC")]
        {:gap, _, _} -> []
      end
    end)
    |> Enum.take(rule.count)
    |> Enum.with_index(1)
    |> Enum.filter(fn {dt, _} -> DateTime.compare(dt, until) == :lt end)
  end
end
