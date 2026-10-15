defmodule ExBooking.CivilRecurrenceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.CivilRecurrence
  alias ExBooking.TimeZoneProvider

  doctest ExBooking.CivilOccurrence
  doctest CivilRecurrence

  defmodule Provider do
    @moduledoc false

    @behaviour TimeZoneProvider

    @impl TimeZoneProvider
    def resolve(nominal, zone, context) do
      count(context, :resolve)
      resolve_value(nominal, zone, context)
    end

    defp resolve_value(_, _, "fault"), do: raise("callback implementation fault")
    defp resolve_value(_, _, "private-canary" = context), do: {:error, {:private, context}}
    defp resolve_value(_, _, "malformed"), do: {:ok, %{}}

    defp resolve_value(nominal, _, "wrong-zone"),
      do: {:ok, DateTime.from_naive!(nominal, "Etc/UTC")}

    defp resolve_value(nominal, zone, "reversed") do
      {:ambiguous, first, second} = DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase)
      {:ambiguous, second, first}
    end

    defp resolve_value(nominal, zone, "iana"),
      do: gap(DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase))

    defp resolve_value(nominal, zone, "every-fold") do
      value = %{DateTime.from_naive!(nominal, "Etc/UTC") | time_zone: zone}
      {:ambiguous, %{value | utc_offset: 3600}, value}
    end

    defp resolve_value(%{day: 14}, _, "late-error"), do: {:error, :private_late_payload}

    defp resolve_value(nominal, zone, context) when context in ["duplicate", "order"] do
      offset = adversarial_offset(nominal.day, context)
      value = %{DateTime.from_naive!(nominal, "Etc/UTC") | time_zone: zone, utc_offset: offset}
      Process.put({__MODULE__, :adversarial_roundtrip}, value)
      {:ok, value}
    end

    defp resolve_value(nominal, zone, context) do
      {:ok,
       %{DateTime.from_naive!(nominal, "Etc/UTC") | time_zone: zone, utc_offset: offset(context)}}
    end

    defp adversarial_offset(13, _), do: 0
    defp adversarial_offset(_, "duplicate"), do: 86_400
    defp adversarial_offset(_, "order"), do: 86_401

    @impl TimeZoneProvider
    def localize(instant, zone, context) do
      count(context, :localize)

      case context do
        "iana" ->
          DateTime.shift_zone(instant, zone, Tz.TimeZoneDatabase)

        "reversed" ->
          DateTime.shift_zone(instant, zone, Tz.TimeZoneDatabase)

        "bad-roundtrip" ->
          {:ok, %{DateTime.add(instant, 1) | time_zone: zone}}

        "bad-localize" ->
          {:error, {:private, context}}

        "every-fold" ->
          offset = if instant.hour == 8, do: 3600, else: 0
          {:ok, %{DateTime.add(instant, offset) | time_zone: zone, utc_offset: offset}}

        context when context in ["duplicate", "order"] ->
          {:ok, Process.get({__MODULE__, :adversarial_roundtrip})}

        _ ->
          offset = offset(context)
          {:ok, %{DateTime.add(instant, offset) | time_zone: zone, utc_offset: offset}}
      end
    end

    defp count(context, kind) do
      key = {__MODULE__, context, kind}
      Process.put(key, Process.get(key, 0) + 1)
    end

    defp offset(<<offset::signed-big-32>>), do: offset
    defp offset(_), do: 0
    defp gap({:gap, _, _}), do: :gap
    defp gap(value), do: value
  end

  test "the facade exposes an independent civil query without an RRULE ordinal" do
    Code.ensure_loaded!(ExBooking)
    assert function_exported?(ExBooking, :civil_occurrences, 3)

    assert {:ok, points} =
             ExBooking.civil_occurrences(~T[09:00:00], ~D[2026-07-13], options())

    assert Enum.map(points, &{&1.nominal, &1.starts_at, &1.resolution}) == [
             {~N[2026-07-13 09:00:00], ~U[2026-07-13 09:00:00Z], :unique},
             {~N[2026-07-15 09:00:00], ~U[2026-07-15 09:00:00Z], :unique}
           ]

    refute Map.has_key?(hd(points), :ordinal)

    for policy <- [:second, :both, :reject] do
      assert {:ok, ^points} =
               CivilRecurrence.occurrences(
                 ~T[09:00:00],
                 ~D[2026-07-13],
                 Keyword.put(options(), :fold_policy, policy)
               )
    end
  end

  test "UTC boundaries preserve original points, microseconds and finite local exhaustion" do
    opts = Keyword.merge(options(), from: ~U[2026-07-13 09:00:00.000001Z])
    assert {:ok, [point]} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], opts)
    assert point.starts_at == ~U[2026-07-15 09:00:00Z]
    opts = Keyword.put(opts, :until, point.starts_at)
    assert {:ok, []} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], opts)

    final =
      Keyword.merge(options(),
        days: 1,
        weekdays: [5],
        from: ~U[9999-12-31 00:00:00Z],
        until: ~U[9999-12-31 23:59:59Z]
      )

    assert {:ok, [point]} = CivilRecurrence.occurrences(~T[09:00:00], ~D[9999-12-31], final)
    assert point.starts_at == ~U[9999-12-31 09:00:00Z]

    assert {:error, {:invalid, :civil_occurrences, :days}} =
             CivilRecurrence.occurrences(
               ~T[09:00:00],
               ~D[9999-12-31],
               Keyword.put(final, :days, 2)
             )
  end

  test "independent Stockholm and New York gap/fold literals cover every policy" do
    for {zone, date, time, first, second} <- [
          {"Europe/Stockholm", ~D[2026-10-25], ~T[02:30:00], ~U[2026-10-25 00:30:00Z],
           ~U[2026-10-25 01:30:00Z]},
          {"America/New_York", ~D[2026-11-01], ~T[01:30:00], ~U[2026-11-01 05:30:00Z],
           ~U[2026-11-01 06:30:00Z]}
        ],
        database <- [Tz.TimeZoneDatabase, provider("iana")] do
      opts =
        Keyword.merge(options(),
          days: 1,
          weekdays: [7],
          time_zone: zone,
          time_zone_database: database,
          from: DateTime.add(first, -1),
          until: DateTime.add(second, 1)
        )

      for {policy, expected} <- [first: [first], second: [second], both: [first, second]] do
        assert {:ok, points} =
                 CivilRecurrence.occurrences(time, date, Keyword.put(opts, :fold_policy, policy))

        assert Enum.map(points, & &1.starts_at) == expected

        expected_resolutions =
          case policy do
            :first -> [:first_fold]
            :second -> [:second_fold]
            :both -> [:first_fold, :second_fold]
          end

        assert Enum.map(points, & &1.resolution) == expected_resolutions
        assert Enum.all?(points, &(NaiveDateTime.to_date(&1.nominal) == date))
      end

      assert {:error, {:ambiguous, :civil_occurrences}} =
               CivilRecurrence.occurrences(time, date, Keyword.put(opts, :fold_policy, :reject))

      between = Keyword.put(opts, :from, DateTime.add(first, 1))
      assert {:ok, []} = CivilRecurrence.occurrences(time, date, between)

      assert {:error, {:ambiguous, :civil_occurrences}} =
               CivilRecurrence.occurrences(
                 time,
                 date,
                 Keyword.merge(between, fold_policy: :reject, until: DateTime.add(second, 2))
               )
    end

    for {zone, date} <- [
          {"Europe/Stockholm", ~D[2026-03-29]},
          {"America/New_York", ~D[2026-03-08]}
        ],
        database <- [Tz.TimeZoneDatabase, provider("iana")] do
      opts =
        Keyword.merge(options(),
          days: 1,
          weekdays: [7],
          time_zone: zone,
          time_zone_database: database
        )

      assert {:ok, []} = CivilRecurrence.occurrences(~T[02:30:00], date, opts)
      # This label is outside the UTC window, but policy precedes filtering.
      assert {:error, {:gap, :civil_occurrences}} =
               CivilRecurrence.occurrences(
                 ~T[02:30:00],
                 date,
                 Keyword.put(opts, :gap_policy, :reject)
               )
    end
  end

  test "malformed callers refuse before any provider callback" do
    opts = Keyword.put(options(), :time_zone_database, provider("preflight"))

    bad_options = [
      [],
      %{},
      [{:days, 1} | opts],
      [{:unknown, true} | opts],
      Enum.drop(opts, 1),
      [{:days, 1} | :improper],
      List.duplicate({:unknown, 1}, 100),
      Keyword.put(opts, :days, true),
      Keyword.put(opts, :days, 0),
      Keyword.put(opts, :days, 367),
      Keyword.put(opts, :weekdays, []),
      Keyword.put(opts, :weekdays, [1, 1]),
      Keyword.put(opts, :weekdays, [3, 1]),
      Keyword.put(opts, :weekdays, [1 | :improper]),
      Keyword.put(opts, :weekdays, List.duplicate(1, 100)),
      Keyword.put(opts, :weekdays, [1.0]),
      Keyword.put(opts, :from, Map.put(opts[:from], :extra, true)),
      Keyword.put(opts, :from, %{opts[:from] | utc_offset: false}),
      Keyword.put(opts, :until, %{opts[:until] | microsecond: {1_000_000, 6}}),
      Keyword.put(opts, :until, opts[:from]),
      Keyword.put(opts, :from, %{opts[:from] | time_zone: String.duplicate("z", 257)}),
      Keyword.put(opts, :from, %{opts[:from] | zone_abbr: String.duplicate("z", 257)}),
      Keyword.put(opts, :from, %{opts[:from] | zone_abbr: <<255>>}),
      Keyword.put(opts, :time_zone, <<255>>),
      Keyword.put(opts, :time_zone, String.duplicate("z", 257)),
      Keyword.put(opts, :time_zone_database, String),
      Keyword.put(opts, :time_zone_database, Map.put(provider("preflight"), :extra, true)),
      Keyword.put(opts, :gap_policy, :snap),
      Keyword.put(opts, :fold_policy, :last)
    ]

    for bad <- bad_options do
      assert {:error, {:invalid, :civil_occurrences, _}} =
               CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], bad)
    end

    for time <- [
          nil,
          %{~T[09:00:00] | hour: true},
          ~T[09:00:00.000000],
          Map.put(~T[09:00:00], :extra, true)
        ] do
      assert {:error, {:invalid, :civil_occurrences, :time}} =
               CivilRecurrence.occurrences(time, ~D[2026-07-13], opts)
    end

    for date <- [
          nil,
          %{~D[2026-07-13] | month: true},
          %{~D[2026-07-13] | year: -1},
          Map.put(~D[2026-07-13], :extra, true)
        ] do
      assert {:error, {:invalid, :civil_occurrences, :first_date}} =
               CivilRecurrence.occurrences(~T[09:00:00], date, opts)
    end

    assert Process.get({Provider, "preflight", :resolve}, 0) == 0
    assert Process.get({Provider, "preflight", :localize}, 0) == 0
  end

  test "civil offset profile is explicit and leaves the existing helpers unchanged" do
    for offset <- [-89_999, -86_400, 86_400, 93_599] do
      context = <<offset::signed-big-32>>

      opts =
        Keyword.merge(options(),
          days: 1,
          weekdays: [1],
          time_zone: "Fixture/Fixed",
          time_zone_database: provider(context),
          from: ~U[2026-07-11 00:00:00Z],
          until: ~U[2026-07-16 00:00:00Z]
        )

      assert {:ok, [point]} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], opts)
      assert point.starts_at == DateTime.add(~U[2026-07-13 09:00:00Z], -offset)

      if abs(offset) > 86_400 do
        assert {:error, :invalid_time_zone_result} =
                 TimeZoneProvider.from_naive(
                   ~N[2026-07-13 09:00:00],
                   "Fixture/Fixed",
                   provider(context)
                 )
      end
    end

    for offset <- [-90_000, 93_600] do
      opts =
        Keyword.merge(options(),
          days: 1,
          time_zone: "Fixture/Fixed",
          time_zone_database: provider(<<offset::signed-big-32>>)
        )

      assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
               CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], opts)
    end
  end

  test "provider work stays finite and errors retain no callback payload" do
    opts =
      Keyword.merge(options(),
        days: 366,
        weekdays: Enum.to_list(1..7),
        time_zone: "Fixture/Fixed",
        time_zone_database: provider("count"),
        from: ~U[2026-01-01 00:00:00Z],
        until: ~U[2027-01-03 00:00:00Z]
      )

    assert {:ok, points} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-01-01], opts)
    assert length(points) == 366
    assert Process.get({Provider, "count", :resolve}) == 366
    assert Process.get({Provider, "count", :localize}) == 366

    folds =
      Keyword.put(opts, :time_zone_database, provider("every-fold"))
      |> Keyword.put(:fold_policy, :both)

    assert {:ok, points} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-01-01], folds)
    assert length(points) == 732
    assert Process.get({Provider, "every-fold", :resolve}) == 366
    assert Process.get({Provider, "every-fold", :localize}) == 732

    for context <- ["private-canary", "malformed", "wrong-zone", "bad-roundtrip", "bad-localize"] do
      result =
        CivilRecurrence.occurrences(
          ~T[09:00:00],
          ~D[2026-07-13],
          Keyword.merge(options(),
            time_zone: "Fixture/Fixed",
            time_zone_database: provider(context)
          )
        )

      assert result == {:error, {:invalid, :civil_occurrences, :time_zone_result}}
      refute inspect(result) =~ context
    end

    assert_raise RuntimeError, "callback implementation fault", fn ->
      CivilRecurrence.occurrences(
        ~T[09:00:00],
        ~D[2026-07-13],
        Keyword.put(options(), :time_zone_database, provider("fault"))
      )
    end

    late =
      Keyword.merge(options(),
        days: 2,
        weekdays: [1, 2],
        time_zone: "Fixture/Fixed",
        time_zone_database: provider("late-error")
      )

    assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
             CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], late)

    assert Process.get({Provider, "late-error", :resolve}) == 2
    assert Process.get({Provider, "late-error", :localize}) == 1
  end

  test "UTC ordering is independent of local order and duplicate points refuse" do
    opts =
      Keyword.merge(options(),
        days: 2,
        weekdays: [1, 2],
        time_zone: "Fixture/Adversarial",
        time_zone_database: provider("order"),
        from: ~U[2026-07-12 00:00:00Z]
      )

    assert {:ok, points} = CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], opts)

    assert Enum.map(points, & &1.starts_at) == [
             ~U[2026-07-13 08:59:59Z],
             ~U[2026-07-13 09:00:00Z]
           ]

    assert Enum.map(points, &NaiveDateTime.to_date(&1.nominal)) == [
             ~D[2026-07-14],
             ~D[2026-07-13]
           ]

    assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
             CivilRecurrence.occurrences(
               ~T[09:00:00],
               ~D[2026-07-13],
               Keyword.put(opts, :time_zone_database, provider("duplicate"))
             )
  end

  test "reversed folds and UTC conversion outside supported years do not become exhaustion" do
    opts =
      Keyword.merge(options(),
        days: 1,
        weekdays: [7],
        time_zone: "Europe/Stockholm",
        time_zone_database: provider("reversed"),
        from: ~U[2026-10-24 00:00:00Z],
        until: ~U[2026-10-27 00:00:00Z]
      )

    assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
             CivilRecurrence.occurrences(~T[02:30:00], ~D[2026-10-25], opts)

    opts =
      Keyword.merge(options(),
        days: 1,
        weekdays: Enum.to_list(1..7),
        time_zone: "Fixture/Fixed",
        time_zone_database: provider(<<93_599::signed-big-32>>),
        from: ~U[0000-01-01 00:00:00Z],
        until: ~U[0000-01-03 00:00:00Z]
      )

    assert {:error, {:invalid, :civil_occurrences, :coordinate_range}} =
             CivilRecurrence.occurrences(~T[09:00:00], ~D[0000-01-01], opts)

    outside = %{opts[:from] | time_zone: "Fixture/Fixed", utc_offset: 93_599}

    assert {:error, {:invalid, :civil_occurrences, :coordinate_range}} =
             CivilRecurrence.occurrences(
               ~T[09:00:00],
               ~D[2026-07-13],
               Keyword.put(opts, :from, outside)
             )
  end

  property "UTC weekday patterns agree with an independent Gregorian oracle and partition union" do
    check all(
            day <- integer(0..365),
            days <- integer(2..32),
            hour <- integer(0..23),
            minute <- integer(0..59),
            mask <- integer(1..127)
          ) do
      weekdays =
        for weekday <- 1..7, rem(div(mask, Integer.pow(2, weekday - 1)), 2) == 1, do: weekday

      first = Date.add(~D[2026-01-01], day)
      from = DateTime.new!(first, ~T[00:00:00], "Etc/UTC")

      opts =
        Keyword.merge(options(),
          days: days,
          weekdays: Enum.sort(weekdays),
          from: from,
          until: DateTime.add(from, days * 86_400)
        )

      time = Time.new!(hour, minute, 0)
      assert {:ok, points} = CivilRecurrence.occurrences(time, first, opts)
      base = :calendar.date_to_gregorian_days(Date.to_erl(first))

      expected =
        for n <- 0..(days - 1),
            date = :calendar.gregorian_days_to_date(base + n),
            :calendar.day_of_the_week(date) in weekdays do
          seconds =
            :calendar.datetime_to_gregorian_seconds({date, {hour, minute, 0}}) - 62_167_219_200

          DateTime.from_unix!(seconds)
        end

      assert Enum.map(points, & &1.starts_at) == expected
      split = div(days, 2)

      assert {:ok, left} =
               CivilRecurrence.occurrences(time, first, Keyword.put(opts, :days, split))

      assert {:ok, right} =
               CivilRecurrence.occurrences(
                 time,
                 Date.add(first, split),
                 Keyword.put(opts, :days, days - split)
               )

      assert left ++ right == points
      assert CivilRecurrence.occurrences(time, first, opts) == {:ok, points}
    end
  end

  defp provider(context) do
    {:ok, provider} = TimeZoneProvider.new(Provider, context)
    provider
  end

  defp options do
    [
      days: 5,
      weekdays: [1, 3],
      from: ~U[2026-07-13 09:00:00Z],
      until: ~U[2026-07-17 00:00:00Z],
      time_zone: "Etc/UTC",
      time_zone_database: Calendar.UTCOnlyTimeZoneDatabase,
      gap_policy: :skip,
      fold_policy: :first
    ]
  end
end
