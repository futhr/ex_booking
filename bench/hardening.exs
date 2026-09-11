Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
base = ~U[2026-07-13 00:00:00Z]

intervals =
  for i <- 1..1_000,
      do:
        ExBooking.Interval.new!(
          DateTime.add(base, i, :minute),
          DateTime.add(base, i + 1, :minute)
        )

events =
  for i <- 1..800 do
    %{
      "@type" => "Event",
      "start" =>
        base
        |> DateTime.add(i, :minute)
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601(),
      "timeZone" => "Etc/UTC",
      "duration" => "PT1S"
    }
  end

nested =
  for n <- [100, 400, 800], into: %{} do
    group =
      events
      |> Enum.take(n)
      |> Enum.reduce(%{"@type" => "Group", "entries" => []}, fn e, g ->
        %{"@type" => "Group", "entries" => [e, g]}
      end)

    {"nested Group #{n}", fn -> ExBooking.JSCalendar.busy_intervals(group) end}
  end

flat = %{"@type" => "Group", "entries" => Enum.take(events, 500)}

ics =
  Enum.take(intervals, 500)
  |> Enum.map_join("\n", fn i ->
    "FREEBUSY:" <> Calendar.strftime(i.start_at, "%Y%m%dT%H%M%SZ") <> "/PT1S"
  end)

rule = %ExBooking.AvailabilityRule{
  timezone: "Europe/Stockholm",
  windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}]
}

finish = DateTime.add(base, 84, :day)
recurrence_finish = DateTime.add(base, 501, :day)

scenarios =
  Map.merge(nested, %{
    "flat Group 500" => fn -> ExBooking.JSCalendar.busy_intervals(flat) end,
    "ICS 500" => fn -> ExBooking.ICalendar.free_busy(ics) end,
    "daily recurrence 500" => fn ->
      ExBooking.RRule.expand("FREQ=DAILY;COUNT=500", base, 30, base, recurrence_finish)
    end,
    "interval constructors 1000" => fn ->
      Enum.map(intervals, &ExBooking.Interval.new(&1.start_at, &1.end_at))
    end,
    "schedule 12 weeks" => fn -> ExBooking.Schedule.expand(rule, base, finish) end
  })

Enum.each(scenarios, fn {_, fun} ->
  case fun.() do
    {:ok, [_ | _]} -> :ok
    [_ | _] -> :ok
    other -> raise "unexpected benchmark result: #{inspect(other)}"
  end
end)

Benchee.run(scenarios, warmup: 1, time: 2, memory_time: 1, parallel: 1)
