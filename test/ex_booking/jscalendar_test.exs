defmodule ExBooking.JSCalendarTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExBooking.JSCalendar

  doctest ExBooking.JSCalendar

  describe "busy_intervals/1" do
    test "normalizes a JSCalendar event into a UTC busy interval" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT45M"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-07-13 07:00:00Z]
      assert busy.end_at == ~U[2026-07-13 07:45:00Z]
      assert busy.kind == :busy
    end

    test "normalizes group entries and merges overlapping busy intervals" do
      group = %{
        "@type" => "Group",
        "entries" => [
          %{
            "@type" => "Event",
            "start" => "2026-07-13T09:30:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT45M"
          },
          %{
            "@type" => "Event",
            "start" => "2026-07-13T09:00:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT45M"
          }
        ]
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(group)
      assert busy.start_at == ~U[2026-07-13 07:00:00Z]
      assert busy.end_at == ~U[2026-07-13 08:15:00Z]
    end

    test "ignores free and cancelled events" do
      group = %{
        "@type" => "Group",
        "entries" => [
          %{
            "@type" => "Event",
            "start" => "2026-07-13T09:00:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT30M",
            "freeBusyStatus" => "free"
          },
          %{
            "@type" => "Event",
            "start" => "2026-07-13T10:00:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT30M",
            "status" => "cancelled"
          }
        ]
      }

      assert {:ok, []} = JSCalendar.busy_intervals(group)
    end

    test "applies calendar-day duration before absolute time duration" do
      event = %{
        "@type" => "Event",
        "start" => "2026-03-28T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "P1DT1H"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-03-28 08:00:00Z]
      assert busy.end_at == ~U[2026-03-29 08:00:00Z]
    end

    test "rejects floating times" do
      event = %{"@type" => "Event", "start" => "2026-07-13T09:00:00", "duration" => "PT30M"}

      assert {:error, {:unsupported, :jscalendar, :floating_time}} =
               JSCalendar.busy_intervals(event)
    end

    test "rejects recurrence rules" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M",
        "recurrenceRules" => [%{"@type" => "RecurrenceRule", "frequency" => "weekly"}]
      }

      assert {:error, {:unsupported, :jscalendar, :recurrence}} = JSCalendar.busy_intervals(event)
    end

    test "rejects invalid group entries" do
      assert {:error, {:invalid, :jscalendar, :entries}} =
               JSCalendar.busy_intervals(%{"@type" => "Group", "entries" => "bad"})

      assert {:error, {:invalid, :jscalendar, :entries}} =
               JSCalendar.busy_intervals(%{"@type" => "Group", "entries" => %{}})
    end

    test "rejects unsupported object types and invalid objects" do
      assert {:error, {:unsupported, :jscalendar, "Task"}} =
               JSCalendar.busy_intervals(%{"@type" => "Task"})

      assert {:error, {:invalid, :jscalendar, :object}} = JSCalendar.busy_intervals(%{})
    end

    test "rejects malformed events and propagates nested group errors" do
      assert {:error, {:invalid, :jscalendar, :event}} =
               JSCalendar.busy_intervals(%{"@type" => "Event"})

      assert {:error, {:unsupported, :jscalendar, "Task"}} =
               JSCalendar.busy_intervals(%{
                 "@type" => "Group",
                 "entries" => [%{"@type" => "Task"}]
               })
    end

    test "rejects unsupported free busy statuses" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M",
        "freeBusyStatus" => "tentative"
      }

      assert {:error, {:unsupported, :jscalendar, {:free_busy_status, "tentative"}}} =
               JSCalendar.busy_intervals(event)
    end

    test "rejects invalid starts, timezones, and durations" do
      base = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M"
      }

      assert {:error, {:invalid, :jscalendar, :start}} =
               base
               |> Map.put("start", "2026-07-13")
               |> JSCalendar.busy_intervals()

      assert {:error, {:invalid, :jscalendar, :timezone}} =
               base
               |> Map.put("timeZone", "Bad/Zone")
               |> JSCalendar.busy_intervals()

      assert {:error, {:invalid, :jscalendar, :duration}} =
               base
               |> Map.put("duration", "bad")
               |> JSCalendar.busy_intervals()

      assert {:error, {:invalid, :jscalendar, :duration}} =
               base
               |> Map.put("duration", 30)
               |> JSCalendar.busy_intervals()
    end

    test "resolves ambiguous starts to the first occurrence" do
      event = %{
        "@type" => "Event",
        "start" => "2026-11-01T01:30:00",
        "timeZone" => "America/New_York",
        "duration" => "PT30M"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-11-01 05:30:00Z]
    end

    test "preserves fractional local datetime and duration precision" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00.123456",
        "timeZone" => "Etc/UTC",
        "duration" => "PT0.5S"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-07-13 09:00:00.123456Z]
      assert busy.end_at == ~U[2026-07-13 09:00:00.623456Z]
    end

    test "rejects fractional precision beyond microseconds" do
      base = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Etc/UTC",
        "duration" => "PT1S"
      }

      assert {:error, {:invalid, :jscalendar, :start}} =
               base
               |> Map.put("start", "2026-07-13T09:00:00.1234567")
               |> JSCalendar.busy_intervals()

      assert {:error, {:invalid, :jscalendar, :duration}} =
               base
               |> Map.put("duration", "PT0.1234567S")
               |> JSCalendar.busy_intervals()
    end

    test "rejects non-canonical fractions and invalid duration component order" do
      base = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Etc/UTC",
        "duration" => "PT1S"
      }

      assert {:error, {:invalid, :jscalendar, :start}} =
               base
               |> Map.put("start", "2026-07-13T09:00:00.120")
               |> JSCalendar.busy_intervals()

      for duration <- ["PT0.0S", "PT0.500S", "PT1H1S"] do
        event = Map.put(base, "duration", duration)

        assert {:error, {:invalid, :jscalendar, :duration}} =
                 JSCalendar.busy_intervals(event)
      end
    end

    test "uses the offset before a spring-forward gap" do
      event = %{
        "@type" => "Event",
        "start" => "2026-03-29T02:30:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-03-29 01:30:00Z]
    end

    test "applies calendar days from the requested wall time inside a gap" do
      event = %{
        "@type" => "Event",
        "start" => "2026-03-29T02:30:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "P1D"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-03-29 01:30:00Z]
      assert busy.end_at == ~U[2026-03-30 00:30:00Z]
    end

    test "drops zero-duration events" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm"
      }

      assert {:ok, []} = JSCalendar.busy_intervals(event)
    end
  end

  describe "ExBooking.import_jscalendar_busy/1" do
    test "delegates normalization" do
      event = %{
        "@type" => "Event",
        "start" => "2026-07-13T09:00:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M"
      }

      assert {:ok, [busy]} = ExBooking.import_jscalendar_busy(event)
      assert busy.end_at == ~U[2026-07-13 07:30:00Z]
    end
  end

  @tag audit_finding: "A05"
  test "rejects recurrence additions and exclusions even on a free base event" do
    base = %{
      "@type" => "Event",
      "start" => "2026-07-13T09:00:00",
      "timeZone" => "Etc/UTC",
      "duration" => "PT30M"
    }

    for field <- ["recurrenceRules", "excludedRecurrenceRules", "recurrenceOverrides"],
        status <- ["busy", "free"] do
      event =
        base
        |> Map.put(field, %{})
        |> Map.put("freeBusyStatus", status)

      assert {:error, {:unsupported, :jscalendar, :recurrence}} = JSCalendar.busy_intervals(event)
    end
  end

  @tag audit_finding: "A05"
  test "cancelled events and nested groups cannot hide unsupported recurrence" do
    for field <- ["recurrenceRules", "excludedRecurrenceRules", "recurrenceOverrides"] do
      event = %{"@type" => "Event", "status" => "cancelled", field => %{}}
      group = %{"@type" => "Group", "entries" => [event]}
      assert {:error, {:unsupported, :jscalendar, :recurrence}} = JSCalendar.busy_intervals(event)
      assert {:error, {:unsupported, :jscalendar, :recurrence}} = JSCalendar.busy_intervals(group)
    end
  end

  test "rejects atom keys, ambiguous aliases and non-UTF8 keys before defaults" do
    base = %{
      "@type" => "Event",
      "start" => "2026-07-13T09:00:00",
      "timeZone" => "Etc/UTC"
    }

    for key <- [:duration, <<255>>] do
      event = Map.put(base, key, "PT30M")

      assert {:error, {:invalid, :jscalendar, :object}} = JSCalendar.busy_intervals(event)

      assert {:error, {:invalid, :jscalendar, :object}} =
               JSCalendar.busy_intervals(Map.put(event, "duration", "PT0S"))
    end
  end

  test "duration parsing requires the entire token" do
    event = %{
      "@type" => "Event",
      "start" => "2026-07-13T09:00:00",
      "timeZone" => "Etc/UTC",
      "duration" => "PT30M\n"
    }

    assert {:error, {:invalid, :jscalendar, :duration}} = JSCalendar.busy_intervals(event)
  end

  test "checks duration bounds before calendar arithmetic" do
    base = %{
      "@type" => "Event",
      "start" => "9999-12-31T23:59:59",
      "timeZone" => "Etc/UTC"
    }

    for duration <- ["PT1S", "P1D", "PT99999999999999999999S", "P99999999999999999D"] do
      assert {:error, {:invalid, :jscalendar, :duration}} =
               JSCalendar.busy_intervals(Map.put(base, "duration", duration))
    end

    assert {:ok, [busy]} =
             JSCalendar.busy_intervals(Map.put(base, "duration", "PT0.999999S"))

    assert busy.end_at == ~U[9999-12-31 23:59:59.999999Z]
  end

  test "nested traversal preserves the first error in entry order" do
    first = %{"@type" => "Event", "duration" => "bad"}
    second = %{"@type" => "Task"}

    assert {:error, {:invalid, :jscalendar, :event}} =
             JSCalendar.busy_intervals(%{
               "@type" => "Group",
               "entries" => [%{"@type" => "Group", "entries" => [first]}, second]
             })
  end

  test "calendar-day durations preserve both zones' spring and autumn transitions" do
    for {zone, start, hours} <- [
          {"Europe/Stockholm", "2026-03-28T09:00:00", 23},
          {"America/New_York", "2026-03-07T09:00:00", 23},
          {"Europe/Stockholm", "2026-10-24T09:00:00", 25},
          {"America/New_York", "2026-10-31T09:00:00", 25}
        ] do
      event = %{"@type" => "Event", "start" => start, "timeZone" => zone, "duration" => "P1D"}
      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert DateTime.diff(busy.end_at, busy.start_at, :hour) == hours
    end
  end

  test "rejects starts whose timezone offset leaves the four-digit UTC year range" do
    for {zone, start} <- [
          {"Etc/GMT-1", "0000-01-01T00:00:00"},
          {"Etc/GMT+1", "9999-12-31T23:59:59"}
        ] do
      event = %{"@type" => "Event", "start" => start, "timeZone" => zone, "duration" => "PT1S"}
      assert {:error, {:invalid, :jscalendar, :start}} = JSCalendar.busy_intervals(event)
    end
  end

  property "group nesting preserves the complete busy union" do
    check all(offsets <- list_of(integer(0..120), min_length: 1, max_length: 40)) do
      events =
        Enum.map(offsets, fn offset ->
          %{
            "@type" => "Event",
            "start" =>
              ~N[2026-07-13 09:00:00]
              |> NaiveDateTime.add(offset, :minute)
              |> NaiveDateTime.to_iso8601(),
            "timeZone" => "Etc/UTC",
            "duration" => "PT30M"
          }
        end)

      nested =
        Enum.reduce(events, %{"@type" => "Group", "entries" => []}, fn event, group ->
          %{"@type" => "Group", "entries" => [event, group]}
        end)

      assert JSCalendar.busy_intervals(nested) ==
               JSCalendar.busy_intervals(%{"@type" => "Group", "entries" => events})
    end
  end
end
