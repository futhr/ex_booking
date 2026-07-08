defmodule ExBooking.JSCalendarTest do
  use ExUnit.Case, async: true

  alias ExBooking.JSCalendar

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
        "entries" => %{
          "b" => %{
            "@type" => "Event",
            "start" => "2026-07-13T09:30:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT45M"
          },
          "a" => %{
            "@type" => "Event",
            "start" => "2026-07-13T09:00:00",
            "timeZone" => "Europe/Stockholm",
            "duration" => "PT45M"
          }
        }
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

    test "snaps spring-forward gap starts forward" do
      event = %{
        "@type" => "Event",
        "start" => "2026-03-29T02:30:00",
        "timeZone" => "Europe/Stockholm",
        "duration" => "PT30M"
      }

      assert {:ok, [busy]} = JSCalendar.busy_intervals(event)
      assert busy.start_at == ~U[2026-03-29 01:00:00Z]
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
end
