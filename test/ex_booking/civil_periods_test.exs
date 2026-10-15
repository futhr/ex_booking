defmodule ExBooking.CivilPeriodsTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.TimeZoneProvider

  defmodule Periods do
    @moduledoc false

    @behaviour TimeZoneProvider

    @impl TimeZoneProvider
    def resolve(nominal, zone, context) do
      case resolve_civil(nominal, zone, context) do
        {:ambiguous, [first, second]} -> {:ambiguous, first, second}
        {:ambiguous, _} -> {:error, :legacy_multiplicity}
        result -> result
      end
    end

    @impl TimeZoneProvider
    def resolve_civil(nominal, zone, context) do
      wall = DateTime.from_naive!(nominal, "Etc/UTC")

      values =
        for offset <- [7200, 3600, 0],
            instant = DateTime.add(wall, -offset),
            offset_at(instant, context) == offset,
            do: %{wall | time_zone: zone, utc_offset: offset}

      case values do
        [unique] -> {:ok, unique}
        [] -> :gap
        alternatives -> {:ambiguous, alternatives}
      end
    end

    @impl TimeZoneProvider
    def localize(instant, zone, context) do
      offset = offset_at(instant, context)
      {:ok, %{DateTime.add(instant, offset) | time_zone: zone, utc_offset: offset}}
    end

    defp offset_at(instant, <<first::signed-64, second::signed-64>>) do
      unix = DateTime.to_unix(instant)

      cond do
        unix < first -> 7200
        unix < second -> 3600
        true -> 0
      end
    end
  end

  test "successive rollbacks retain all original instants at period boundaries" do
    date = ~D[2026-07-13]
    provider = provider(date)

    for {time, offsets} <- [
          {~T[08:59:59], [7200]},
          {~T[09:00:00], [7200, 3600, 0]},
          {~T[09:30:00], [7200, 3600, 0]},
          {~T[09:59:59], [7200, 3600, 0]},
          {~T[10:00:00], [0]}
        ] do
      assert {:ok, points} = query(date, time, provider)
      wall = DateTime.new!(date, time)

      assert Enum.map(points, & &1.starts_at) ==
               Enum.map(offsets, &DateTime.add(wall, -&1))

      assert Enum.all?(points, &(&1.nominal == NaiveDateTime.new!(date, time)))
    end

    assert {:ok, [third]} =
             query(date, ~T[09:30:00], provider, from: ~U[2026-07-13 09:00:00Z])

    assert third.starts_at == ~U[2026-07-13 09:30:00Z]
    assert third.resolution == {:fold, 3}

    assert {:error, :time_zone_provider_refused} =
             TimeZoneProvider.from_naive(~N[2026-07-13 09:30:00], "Synthetic/Periods", provider)
  end

  property "independent immutable period tables do not change another query" do
    check all(day <- integer(0..365), second <- integer(0..3599)) do
      date = Date.add(~D[2026-01-01], day)
      other_date = Date.add(date, 366)
      first = provider(date)
      other = provider(other_date)
      time = Time.add(~T[09:00:00], second)

      assert {:ok, points} = query(date, time, first)
      wall = DateTime.new!(date, time)

      assert Enum.map(points, & &1.starts_at) ==
               [DateTime.add(wall, -7200), DateTime.add(wall, -3600), wall]

      assert {:ok, [_]} = query(date, time, other)
      assert {:ok, other_points} = query(other_date, time, other)
      assert length(other_points) == 3
      assert query(date, time, first) == {:ok, points}
    end
  end

  defp provider(date) do
    first =
      date
      |> DateTime.new!(~T[08:00:00])
      |> DateTime.to_unix()

    {:ok, provider} = TimeZoneProvider.new(Periods, <<first::signed-64, first + 3600::signed-64>>)
    provider
  end

  defp query(date, time, provider, changes \\ []) do
    from = DateTime.new!(date, ~T[00:00:00])

    opts = [
      days: 1,
      weekdays: [Date.day_of_week(date)],
      from: from,
      until: DateTime.add(from, 86_400),
      time_zone: "Synthetic/Periods",
      time_zone_database: provider,
      gap_policy: :skip,
      fold_policy: :both
    ]

    ExBooking.civil_occurrences(time, date, Keyword.merge(opts, changes))
  end
end
