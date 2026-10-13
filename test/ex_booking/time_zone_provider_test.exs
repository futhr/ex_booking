defmodule ExBooking.TimeZoneProviderTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.TimeZoneProvider

  doctest TimeZoneProvider

  defmodule ExplicitZone do
    @moduledoc false

    @behaviour TimeZoneProvider

    @impl TimeZoneProvider
    def resolve(nominal, zone, "iana"),
      do: DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase) |> gap()

    def resolve(nominal, zone, "reversed") do
      {:ambiguous, first, second} = DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase)
      {:ambiguous, second, first}
    end

    def resolve(nominal, zone, "wrong-wall") do
      datetime =
        nominal
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.add(1)

      {:ok, %{datetime | time_zone: zone}}
    end

    def resolve(nominal, zone, "precision") do
      datetime = DateTime.from_naive!(nominal, "Etc/UTC")
      {:ok, %{datetime | time_zone: zone, microsecond: {0, 6}}}
    end

    def resolve(_, _, "malformed"), do: {:ok, %{}}
    def resolve(_, _, "error"), do: {:error, :time_zone_not_found}
    def resolve(_, _, "gap"), do: :gap

    def resolve(nominal, zone, <<offset::signed-big-32>>) do
      local = DateTime.from_naive!(nominal, "Etc/UTC")
      {:ok, %{local | time_zone: zone, utc_offset: offset, zone_abbr: "FIXED"}}
    end

    def resolve(_, _, _), do: :invalid

    @impl TimeZoneProvider
    def localize(datetime, zone, "iana"),
      do: DateTime.shift_zone(datetime, zone, Tz.TimeZoneDatabase)

    def localize(datetime, zone, "wrong-wall"),
      do: {:ok, %{DateTime.add(datetime, 1) | time_zone: zone}}

    def localize(datetime, zone, "precision"),
      do: {:ok, %{datetime | time_zone: zone, microsecond: {0, 6}}}

    def localize(_, _, "malformed"), do: {:ok, nil}
    def localize(_, _, "error"), do: {:error, :time_zone_not_found}

    def localize(datetime, zone, <<offset::signed-big-32>>) do
      local =
        datetime
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.add(offset, :second)

      {:ok, %{local | time_zone: zone, utc_offset: offset, zone_abbr: "FIXED"}}
    end

    def localize(_, _, _), do: :invalid

    defp gap({:gap, _, _}), do: :gap
    defp gap(result), do: result
  end

  test "two immutable contexts stay independent in recurrence and cursor identity" do
    for offset <- [0, 3600] do
      {:ok, provider} = TimeZoneProvider.new(ExplicitZone, <<offset::signed-big-32>>)

      {:ok, start} =
        TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Fixture/Fixed", provider)

      assert {:ok, first} =
               ExBooking.occurrences("FREQ=DAILY;COUNT=3", start, options(provider, limit: 1))

      expected = DateTime.add(~U[2026-07-13 06:00:00Z], -offset)
      assert hd(first.occurrences).starts_at == expected
      assert hd(first.occurrences).nominal == ~N[2026-07-13 06:00:00]

      assert {:ok, rest} =
               ExBooking.occurrences(
                 "FREQ=DAILY;COUNT=3",
                 start,
                 options(provider, cursor: first.next_cursor, limit: 3)
               )

      assert Enum.map(rest.occurrences, & &1.ordinal) == [2, 3]
      changed = %{provider | context: <<offset + 60::signed-big-32>>}

      {:ok, changed_start} =
        TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Fixture/Fixed", changed)

      assert {:error, {:stale, :occurrences, :cursor_basis}} =
               ExBooking.occurrences(
                 "FREQ=DAILY;COUNT=3",
                 changed_start,
                 options(changed, cursor: first.next_cursor)
               )
    end
  end

  test "both DST zones preserve independent gap/fold UTC coordinates and module parity" do
    {:ok, provider} = TimeZoneProvider.new(ExplicitZone, "iana")

    cases = [
      {"Europe/Stockholm", ~N[2026-03-28 02:30:00], ~U[2026-04-01 00:00:00Z],
       [~U[2026-03-28 01:30:00Z], ~U[2026-03-30 00:30:00Z], ~U[2026-03-31 00:30:00Z]]},
      {"America/New_York", ~N[2026-03-07 02:30:00], ~U[2026-03-11 00:00:00Z],
       [~U[2026-03-07 07:30:00Z], ~U[2026-03-09 06:30:00Z], ~U[2026-03-10 06:30:00Z]]},
      {"Europe/Stockholm", ~N[2026-10-24 02:30:00], ~U[2026-10-28 00:00:00Z],
       [~U[2026-10-24 00:30:00Z], ~U[2026-10-25 00:30:00Z], ~U[2026-10-26 01:30:00Z]]},
      {"America/New_York", ~N[2026-10-31 01:30:00], ~U[2026-11-04 00:00:00Z],
       [~U[2026-10-31 05:30:00Z], ~U[2026-11-01 05:30:00Z], ~U[2026-11-02 06:30:00Z]]}
    ]

    for {zone, nominal, until, expected} <- cases do
      {:ok, start} = TimeZoneProvider.from_naive(nominal, zone, provider)
      opts = options(provider, from: DateTime.add(hd(expected), -3600), until: until)
      assert {:ok, actual} = ExBooking.occurrences("FREQ=DAILY;COUNT=3", start, opts)
      assert Enum.map(actual.occurrences, & &1.starts_at) == expected

      assert ExBooking.occurrences(
               "FREQ=DAILY;COUNT=3",
               start,
               Keyword.put(opts, :time_zone_database, Tz.TimeZoneDatabase)
             ) == {:ok, actual}
    end

    for {zone, nominal, expected} <- [
          {"Europe/Stockholm", ~N[2026-10-25 02:30:00], ~U[2026-10-25 01:30:00Z]},
          {"America/New_York", ~N[2026-11-01 01:30:00], ~U[2026-11-01 06:30:00Z]}
        ] do
      {:ambiguous, _, second} = TimeZoneProvider.from_naive(nominal, zone, provider)

      opts =
        options(provider, from: DateTime.add(expected, -1), until: DateTime.add(expected, 60))

      assert {:ok, %{occurrences: [occurrence]}} =
               ExBooking.occurrences("FREQ=DAILY;COUNT=1", second, opts)

      assert occurrence.starts_at == expected
      assert occurrence.resolution == :second_fold
    end
  end

  property "explicit fixed offsets retain exact originals and page-size independence" do
    check all(offset <- integer(-12..12), count <- integer(1..10), page_size <- integer(1..4)) do
      {:ok, provider} = TimeZoneProvider.new(ExplicitZone, <<offset * 3600::signed-big-32>>)

      {:ok, start} =
        TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Fixture/Fixed", provider)

      opts =
        options(provider,
          from: ~U[2026-07-12 00:00:00Z],
          until: ~U[2026-08-01 00:00:00Z],
          limit: page_size
        )

      rule = "FREQ=DAILY;COUNT=#{count}"
      occurrences = pages(rule, start, opts, nil, [])

      assert Enum.map(occurrences, & &1.starts_at) ==
               Enum.map(
                 0..(count - 1),
                 &DateTime.add(~U[2026-07-13 06:00:00Z], &1 * 86_400 - offset * 3600)
               )

      assert Enum.map(occurrences, & &1.ordinal) == Enum.to_list(1..count)
    end
  end

  test "forged providers, malformed coordinates and output faults refuse explicitly" do
    {:ok, provider} = TimeZoneProvider.new(ExplicitZone, "malformed")
    assert TimeZoneProvider.valid?(provider)

    for {module, context} <- [
          {String, <<>>},
          {nil, <<>>},
          {"unknown", <<>>},
          {ExplicitZone, nil},
          {ExplicitZone, :binary.copy(<<0>>, 1_048_577)}
        ] do
      assert TimeZoneProvider.new(module, context) == {:error, :invalid_time_zone_provider}
    end

    assert {:ok, _} = TimeZoneProvider.new(ExplicitZone, :binary.copy(<<0>>, 1_048_576))
    refute TimeZoneProvider.valid?(Map.put(provider, :extra, true))

    assert {:error, :invalid_time_zone_result} =
             TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Etc/UTC", provider)

    assert {:error, :invalid_time_zone_result} =
             TimeZoneProvider.shift_zone(~U[2026-07-13 06:00:00Z], "Etc/UTC", provider)

    assert {:error, :invalid_time_zone_provider} =
             TimeZoneProvider.from_naive(nil, "Etc/UTC", provider)

    assert {:error, :invalid_time_zone_provider} =
             TimeZoneProvider.shift_zone(nil, "Etc/UTC", provider)

    assert {:error, :invalid_time_zone_provider} =
             TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Etc/UTC", nil)

    assert {:error, :invalid_time_zone_provider} =
             TimeZoneProvider.shift_zone(~U[2026-07-13 06:00:00Z], "Etc/UTC", nil)

    {:ok, reverse} = TimeZoneProvider.new(ExplicitZone, "reversed")

    assert {:error, :invalid_time_zone_result} =
             TimeZoneProvider.from_naive(~N[2026-10-25 02:30:00], "Europe/Stockholm", reverse)

    {:ok, errors} = TimeZoneProvider.new(ExplicitZone, "error")

    assert {:error, :time_zone_not_found} =
             TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Etc/UTC", errors)

    assert {:error, :time_zone_not_found} =
             TimeZoneProvider.shift_zone(~U[2026-07-13 06:00:00Z], "Etc/UTC", errors)

    {:ok, gap} = TimeZoneProvider.new(ExplicitZone, "gap")
    assert :gap = TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Etc/UTC", gap)
    {:ok, bad} = TimeZoneProvider.new(ExplicitZone, "unknown")

    assert {:error, :invalid_time_zone_result} =
             TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Etc/UTC", bad)

    assert {:error, :invalid_time_zone_result} =
             TimeZoneProvider.shift_zone(~U[2026-07-13 06:00:00Z], "Etc/UTC", bad)
  end

  test "changed wall, instant, precision and offset overflow are invalid results" do
    for context <- ["wrong-wall", "precision", <<86_401::signed-big-32>>] do
      {:ok, provider} = TimeZoneProvider.new(ExplicitZone, context)

      assert {:error, :invalid_time_zone_result} =
               TimeZoneProvider.from_naive(~N[2026-07-13 06:00:00], "Fixture/Fixed", provider)

      assert {:error, :invalid_time_zone_result} =
               TimeZoneProvider.shift_zone(~U[2026-07-13 06:00:00Z], "Fixture/Fixed", provider)
    end
  end

  defp options(provider, updates) do
    Keyword.merge(
      [
        from: ~U[2026-07-13 00:00:00Z],
        until: ~U[2026-07-18 00:00:00Z],
        time_zone_database: provider,
        time_zone_basis: "explicit-v1",
        limit: 128,
        work_limit: 128
      ],
      updates
    )
  end

  defp pages(rule, start, opts, cursor, accumulated) do
    {:ok, page} = ExBooking.occurrences(rule, start, Keyword.put(opts, :cursor, cursor))
    result = accumulated ++ page.occurrences
    if page.next_cursor, do: pages(rule, start, opts, page.next_cursor, result), else: result
  end
end
