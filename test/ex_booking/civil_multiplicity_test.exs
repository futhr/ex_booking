defmodule ExBooking.CivilMultiplicityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.TimeZoneProvider

  defmodule Provider do
    @moduledoc false

    @behaviour TimeZoneProvider

    @impl TimeZoneProvider
    def resolve(_, _, _) do
      count(:legacy)
      {:error, :legacy_multiple_unsupported}
    end

    @impl TimeZoneProvider
    def resolve_civil(nominal, zone, <<size::16, mode::8>>) do
      count(:resolve)
      wall = DateTime.from_naive!(nominal, "Etc/UTC")
      values = for index <- 1..size, do: %{wall | time_zone: zone, utc_offset: size - index}
      result(mode, values)
    end

    defp result(1, values), do: {:ambiguous, Enum.reverse(values)}

    defp result(2, values),
      do: {:ambiguous, List.update_at(values, -1, &Map.put(&1, :extra, true))}

    defp result(3, [first | rest]), do: {:ambiguous, [first, first | rest]}
    defp result(4, _), do: {:ambiguous, []}
    defp result(5, [first | _]), do: {:ambiguous, [first]}
    defp result(6, [first | _]), do: {:ambiguous, [first | :improper]}
    defp result(7, _), do: {:error, :private_multiple_canary}
    defp result(8, _), do: raise("synthetic complete resolver fault")
    defp result(9, [first | _]), do: {:ok, first}
    defp result(10, _), do: :gap
    defp result(_, values), do: {:ambiguous, values}

    @impl TimeZoneProvider
    def localize(utc, zone, _) do
      count(:localize)
      offset = 9 * 3600 - (utc.hour * 3600 + utc.minute * 60 + utc.second)
      {:ok, %{DateTime.add(utc, offset) | time_zone: zone, utc_offset: offset}}
    end

    defp count(kind) do
      key = {__MODULE__, kind}
      Process.put(key, Process.get(key, 0) + 1)
    end
  end

  defmodule LegacyListProvider do
    @moduledoc false

    @behaviour TimeZoneProvider

    @impl TimeZoneProvider
    def resolve(nominal, zone, context), do: Provider.resolve_civil(nominal, zone, context)

    @impl TimeZoneProvider
    def localize(utc, zone, context), do: Provider.localize(utc, zone, context)
  end

  test "complete ambiguities preserve every original UTC coordinate and local position" do
    for count <- [2, 3, 9, 732] do
      assert {:ok, points} = query(count)
      assert length(points) == count
      base = DateTime.to_unix(~U[2026-07-13 09:00:00Z])

      assert Enum.map(points, &DateTime.to_unix(&1.starts_at)) ==
               Enum.to_list((base - count + 1)..base)

      assert Enum.all?(points, &(&1.nominal == ~N[2026-07-13 09:00:00]))
      assert Enum.map(points, & &1.resolution) == for(index <- 1..count, do: position(index))
      assert query(count) == {:ok, points}
    end
  end

  test "all policies operate on the complete set before the UTC horizon" do
    for policy <- [:first, :second, :both] do
      assert {:ok, points} = query(3, 0, fold_policy: policy)

      expected =
        case policy do
          :first -> [~U[2026-07-13 08:59:58Z]]
          :second -> [~U[2026-07-13 08:59:59Z]]
          :both -> [~U[2026-07-13 08:59:58Z], ~U[2026-07-13 08:59:59Z], ~U[2026-07-13 09:00:00Z]]
        end

      assert Enum.map(points, & &1.starts_at) == expected
    end

    assert {:ok, []} = query(3, 0, fold_policy: :first, from: ~U[2026-07-13 08:59:59Z])
    assert {:ok, [second]} = query(3, 0, fold_policy: :second, from: ~U[2026-07-13 08:59:59Z])
    assert second.resolution == :second_fold
    assert {:ok, [second, third]} = query(3, 0, from: ~U[2026-07-13 08:59:59Z])
    assert second.resolution == :second_fold and third.resolution == {:fold, 3}

    assert {:error, {:ambiguous, :civil_occurrences}} =
             query(3, 0,
               fold_policy: :reject,
               from: ~U[2026-07-14 00:00:00Z],
               until: ~U[2026-07-15 00:00:00Z]
             )

    assert {:ok, [_]} = query(3, 9, fold_policy: :reject)
    assert {:ok, []} = query(3, 10)
    assert {:error, {:gap, :civil_occurrences}} = query(3, 10, gap_policy: :reject)
  end

  test "the existing localization ceiling is shared and checked before each complete label" do
    reset()
    assert {:ok, points} = query(366, 0, days: 2, until: ~U[2026-07-15 00:00:00Z])
    assert length(points) == 732
    assert calls(:resolve) == 2 and calls(:localize) == 732 and calls(:legacy) == 0
    reset()

    assert {:error, {:limit, :civil_occurrences, :work}} =
             query(367, 0, days: 2, until: ~U[2026-07-15 00:00:00Z])

    assert calls(:resolve) == 2 and calls(:localize) == 367 and calls(:legacy) == 0
    reset()
    assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} = query(733)
    assert calls(:resolve) == 1 and calls(:localize) == 0
  end

  test "discarded malformed candidates, nonincreasing sets and callback errors never fall back" do
    for mode <- 1..7 do
      reset()

      assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
               query(3, mode, fold_policy: :first)

      assert calls(:legacy) == 0
    end

    assert_raise RuntimeError, "synthetic complete resolver fault", fn -> query(3, 8) end
    assert calls(:legacy) == 0
    reset()
    {:ok, provider} = TimeZoneProvider.new(Provider, <<3::16, 0::8>>)

    assert {:error, :time_zone_provider_refused} =
             TimeZoneProvider.from_naive(~N[2026-07-13 09:00:00], "Synthetic/Multiple", provider)

    assert calls(:legacy) == 1 and calls(:resolve) == 0

    reset()
    {:ok, legacy} = TimeZoneProvider.new(LegacyListProvider, <<3::16, 0::8>>)

    assert {:error, {:invalid, :civil_occurrences, :time_zone_result}} =
             query(3, 0, time_zone_database: legacy)

    assert calls(:resolve) == 1 and calls(:localize) == 0
  end

  defp query(count, mode \\ 0, changes \\ []) do
    {:ok, provider} = TimeZoneProvider.new(Provider, <<count::16, mode::8>>)

    opts = [
      days: 1,
      weekdays: Enum.to_list(1..7),
      from: ~U[2026-07-13 00:00:00Z],
      until: ~U[2026-07-14 00:00:00Z],
      time_zone: "Synthetic/Multiple",
      time_zone_database: provider,
      gap_policy: :skip,
      fold_policy: :both
    ]

    ExBooking.civil_occurrences(~T[09:00:00], ~D[2026-07-13], Keyword.merge(opts, changes))
  end

  defp position(1), do: :first_fold
  defp position(2), do: :second_fold
  defp position(index), do: {:fold, index}
  defp calls(kind), do: Process.get({Provider, kind}, 0)
  defp reset, do: Enum.each([:legacy, :resolve, :localize], &Process.delete({Provider, &1}))
end
