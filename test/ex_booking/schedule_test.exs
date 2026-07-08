defmodule ExBooking.ScheduleTest do
  use ExUnit.Case, async: true

  alias ExBooking.AvailabilityRule
  alias ExBooking.DSTFixtures
  alias ExBooking.Interval
  alias ExBooking.Schedule

  doctest ExBooking.Schedule

  defp rule(overrides) do
    struct!(AvailabilityRule, Map.merge(%{timezone: "Etc/UTC", windows: []}, Map.new(overrides)))
  end

  defp utc(date, time, tz) do
    date
    |> DateTime.new!(time, tz)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  describe "weekly windows" do
    test "expands a weekday window into a UTC interval" do
      # 2026-07-13 is a Monday (ISO weekday 1).
      rule =
        rule(
          timezone: "Europe/Stockholm",
          windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[12:00:00]}]
        )

      assert {:ok, [interval]} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])

      # Stockholm is CEST (UTC+2) in July.
      assert interval.start_at == ~U[2026-07-13 07:00:00Z]
      assert interval.end_at == ~U[2026-07-13 10:00:00Z]
    end

    test "only windows for the date's weekday are expanded" do
      rule = rule(windows: [%{weekday: 2, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}])

      # 2026-07-13 is Monday, not Tuesday.
      assert {:ok, []} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])
    end

    test "results are clipped to the search horizon" do
      rule = rule(windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}])

      assert {:ok, [interval]} =
               Schedule.expand(rule, ~U[2026-07-13 10:00:00Z], ~U[2026-07-13 15:00:00Z])

      assert interval.start_at == ~U[2026-07-13 10:00:00Z]
      assert interval.end_at == ~U[2026-07-13 15:00:00Z]
    end
  end

  describe "cross-midnight windows" do
    test "a window whose end_time <= start_time spills into the next day" do
      rule = rule(windows: [%{weekday: 1, start_time: ~T[22:00:00], end_time: ~T[02:00:00]}])

      assert {:ok, [interval]} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-15 00:00:00Z])

      assert interval.start_at == ~U[2026-07-13 22:00:00Z]
      assert interval.end_at == ~U[2026-07-14 02:00:00Z]
    end
  end

  describe "overrides" do
    test "an override replaces the day's windows" do
      rule =
        rule(
          windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}],
          overrides: [
            %{
              date: ~D[2026-07-13],
              windows: [%{start_time: ~T[13:00:00], end_time: ~T[15:00:00]}]
            }
          ]
        )

      assert {:ok, [interval]} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])

      assert interval.start_at == ~U[2026-07-13 13:00:00Z]
      assert interval.end_at == ~U[2026-07-13 15:00:00Z]
    end

    test "an override with empty windows removes the day" do
      rule =
        rule(
          windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}],
          overrides: [%{date: ~D[2026-07-13], windows: []}]
        )

      assert {:ok, []} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])
    end
  end

  describe "blackouts" do
    test "blackout intervals are subtracted from offerable time" do
      rule =
        rule(
          windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}],
          blackouts: [
            %Interval{start_at: ~U[2026-07-13 12:00:00Z], end_at: ~U[2026-07-13 13:00:00Z]}
          ]
        )

      assert {:ok, [morning, afternoon]} =
               Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])

      assert morning.end_at == ~U[2026-07-13 12:00:00Z]
      assert afternoon.start_at == ~U[2026-07-13 13:00:00Z]
    end
  end

  describe "DST spring-forward (gap → snap forward)" do
    for zone <- DSTFixtures.zones() do
      test "#{zone}: a window starting in the gap snaps its start forward" do
        %{timezone: tz, spring_forward: sf} = DSTFixtures.transitions(unquote(zone))
        weekday = Date.day_of_week(sf.date)

        # Window starts inside the non-existent gap; end is after the transition.
        rule =
          rule(
            timezone: tz,
            windows: [%{weekday: weekday, start_time: sf.gap_starts, end_time: ~T[04:00:00]}]
          )

        from = utc(Date.add(sf.date, -1), ~T[00:00:00], tz)
        until = utc(Date.add(sf.date, 1), ~T[00:00:00], tz)

        assert {:ok, [interval]} = Schedule.expand(rule, from, until)
        # Start snaps to the end of the gap (first valid instant after it).
        assert interval.start_at == utc(sf.date, sf.gap_ends, tz)
      end
    end
  end

  describe "DST spring-forward window collapse" do
    test "a window entirely inside the gap yields no interval" do
      %{timezone: tz, spring_forward: sf} = DSTFixtures.transitions(:stockholm)
      weekday = Date.day_of_week(sf.date)

      # 02:15–02:45 on the transition date is a wall-time range that never
      # exists; both ends snap forward to the same instant, so nothing is offered.
      rule =
        rule(
          timezone: tz,
          windows: [%{weekday: weekday, start_time: ~T[02:15:00], end_time: ~T[02:45:00]}]
        )

      from = utc(Date.add(sf.date, -1), ~T[00:00:00], tz)
      until = utc(Date.add(sf.date, 1), ~T[00:00:00], tz)

      assert {:ok, []} = Schedule.expand(rule, from, until)
    end
  end

  describe "DST fall-back (ambiguous → first occurrence)" do
    for zone <- DSTFixtures.zones() do
      test "#{zone}: a window starting in the ambiguous hour uses the first occurrence" do
        %{timezone: tz, fall_back: fb} = DSTFixtures.transitions(unquote(zone))
        weekday = Date.day_of_week(fb.date)
        start_time = Time.add(fb.ambiguous_starts, 30 * 60)

        rule =
          rule(
            timezone: tz,
            windows: [%{weekday: weekday, start_time: start_time, end_time: ~T[05:00:00]}]
          )

        from = utc(Date.add(fb.date, -1), ~T[00:00:00], tz)
        until = utc(Date.add(fb.date, 1), ~T[12:00:00], tz)

        {:ambiguous, first, _second} = DateTime.new(fb.date, start_time, tz)

        assert {:ok, [interval]} = Schedule.expand(rule, from, until)
        assert interval.start_at == DateTime.shift_zone!(first, "Etc/UTC")
      end
    end
  end
end
