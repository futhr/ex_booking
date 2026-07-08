defmodule ExBooking.Bench do
  @moduledoc false

  alias ExBooking.Assignment
  alias ExBooking.Availability
  alias ExBooking.AvailabilityRule
  alias ExBooking.ICalendar
  alias ExBooking.Interval
  alias ExBooking.JSCalendar
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Resource
  alias ExBooking.RRule
  alias ExBooking.Schedule
  alias ExBooking.Slotting

  @output_dir "bench/output"
  @markdown_file Path.join(@output_dir, "benchmarks.md")

  @base ~U[2026-07-13 00:00:00Z]
  @full_config [warmup: 2, time: 5, memory_time: 1]
  @smoke_config [warmup: 0, time: 0.01, memory_time: 0]

  def run(argv \\ System.argv()) do
    smoke? = "--smoke" in argv
    File.mkdir_p!(@output_dir)

    Benchee.run(
      scenarios(),
      Keyword.merge(bench_config(smoke?),
        percentiles: [50, 95, 99],
        formatters: [
          Benchee.Formatters.Console,
          {Benchee.Formatters.Markdown, file: @markdown_file, description: description(smoke?)}
        ]
      )
    )
  end

  defp bench_config(true), do: @smoke_config
  defp bench_config(false), do: @full_config

  defp scenarios do
    request = request()
    resources = resources(100)
    rules = List.duplicate(rule(), 100)
    meeting_type = meeting_type()
    slot = request.slot

    %{
      "BK.01 interval merge 2k intervals" => fn ->
        Interval.merge(busy_set(2_000, 15, 10))
      end,
      "BK.02 interval subtract 1k busy intervals" => fn ->
        Interval.subtract_all(
          [Interval.new!(@base, DateTime.add(@base, 60, :day))],
          busy_set(1_000)
        )
      end,
      "BK.03 slotting 8 week free interval" => fn ->
        @base
        |> then(&Interval.new!(&1, DateTime.add(&1, 56, :day)))
        |> Slotting.generate_slots(30, 15)
      end,
      "BK.04 schedule expand 12 week business hours" => fn ->
        Schedule.expand(rule(), @base, DateTime.add(@base, 84, :day))
      end,
      "BK.05 availability one host 8 weeks" => fn ->
        ExBooking.available_slots(
          meeting_type,
          [resource("host_1", busy_set(200))],
          [rule()],
          horizon(56)
        )
      end,
      "BK.06 availability collective 10 hosts" => fn ->
        ExBooking.available_slots(
          %{meeting_type | participants: :collective},
          resources(10),
          List.duplicate(rule(), 10),
          horizon(28)
        )
      end,
      "BK.07 availability pool 100 hosts" => fn ->
        ExBooking.available_slots(
          %{meeting_type | participants: :pool, capacity_required: 3},
          resources,
          rules,
          horizon(28)
        )
      end,
      "BK.08 validate request across 100 hosts" => fn ->
        ExBooking.validate_request(request, meeting_type, resources, rules, now: @base)
      end,
      "BK.09 decide with assignment and alternatives" => fn ->
        ExBooking.decide(request, meeting_type, resources, rules,
          now: @base,
          from: @base,
          until: DateTime.add(@base, 7, :day)
        )
      end,
      "BK.10 assignment weighted 1k resources" => fn ->
        Assignment.assign(resources(1_000), slot, strategy: :weighted)
      end,
      "BK.11 rrule daily 500 occurrences" => fn ->
        RRule.expand(
          "FREQ=DAILY;COUNT=500",
          DateTime.add(@base, 9, :hour),
          30,
          @base,
          DateTime.add(@base, 600, :day)
        )
      end,
      "BK.12 rrule weekly byday 500 occurrences" => fn ->
        RRule.expand(
          "FREQ=WEEKLY;COUNT=500;BYDAY=MO,WE,FR",
          DateTime.add(@base, 9, :hour),
          30,
          @base,
          DateTime.add(@base, 1_400, :day)
        )
      end,
      "BK.13 ics freebusy 500 periods" => fn ->
        ICalendar.free_busy(ics_freebusy(500))
      end,
      "BK.14 jscalendar group 500 events" => fn ->
        JSCalendar.busy_intervals(jscalendar_group(500))
      end,
      "BK.15 availability eligible pool request" => fn ->
        Availability.eligible(
          request,
          %{meeting_type | participants: :pool, capacity_required: 3},
          resources,
          rules,
          @base
        )
      end
    }
  end

  defp description(true) do
    "Smoke benchmark run for documentation freshness. Run `mix bench` locally for stable measurements."
  end

  defp description(false) do
    "Benchmark run for ExBooking's interval, availability, assignment, lifecycle, and calendar-data paths."
  end

  defp horizon(days) do
    [now: @base, from: @base, until: DateTime.add(@base, days, :day)]
  end

  defp meeting_type do
    %MeetingType{id: "intro", duration_min: 30, slot_interval_min: 15}
  end

  defp request do
    %Request{
      meeting_type_id: "intro",
      invitee_timezone: "Etc/UTC",
      slot: Interval.new!(DateTime.add(@base, 9, :hour), DateTime.add(@base, 570, :minute))
    }
  end

  defp rule do
    %AvailabilityRule{
      timezone: "Etc/UTC",
      windows:
        for weekday <- 1..5 do
          %{weekday: weekday, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
        end
    }
  end

  defp resources(count) do
    for index <- 1..count do
      resource("host_#{pad(index)}", busy_set(20, 120 + rem(index, 7), 30), index)
    end
  end

  defp resource(id, busy, index \\ 1) do
    %Resource{
      id: id,
      timezone: "Etc/UTC",
      capacity: 2,
      busy: busy,
      fairness: %{
        assignments_count: rem(index, 17),
        last_assigned_at: DateTime.add(@base, -index, :day),
        weight: 1 + rem(index, 5),
        priority: rem(index, 10)
      }
    }
  end

  defp busy_set(count, spacing_min \\ 90, length_min \\ 30) do
    for index <- 0..(count - 1) do
      start_at = DateTime.add(@base, index * spacing_min, :minute)
      Interval.new!(start_at, DateTime.add(start_at, length_min, :minute), kind: :busy)
    end
  end

  defp ics_freebusy(count) do
    values =
      for index <- 0..(count - 1) do
        start_at = DateTime.add(@base, index * 60, :minute)
        end_at = DateTime.add(start_at, 30, :minute)
        "#{format_ics(start_at)}/#{format_ics(end_at)}"
      end

    "BEGIN:VCALENDAR\nBEGIN:VFREEBUSY\nFREEBUSY:#{Enum.join(values, ",")}\nEND:VFREEBUSY\nEND:VCALENDAR"
  end

  defp jscalendar_group(count) do
    entries =
      for index <- 0..(count - 1), into: %{} do
        start_at = DateTime.add(@base, index * 60, :minute)

        {"event_#{pad(index)}",
         %{
           "@type" => "Event",
           "start" => start_at |> DateTime.to_iso8601() |> String.trim_trailing("Z"),
           "timeZone" => "Etc/UTC",
           "duration" => "PT30M"
         }}
      end

    %{"@type" => "Group", "entries" => entries}
  end

  defp format_ics(datetime), do: Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")
  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(4, "0")
end

ExBooking.Bench.run()
