defmodule ExBooking.TemporalValidationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.Availability
  alias ExBooking.AvailabilityRule
  alias ExBooking.Hold
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Resource
  alias ExBooking.RRule
  alias ExBooking.Schedule

  doctest ExBooking.Temporal

  @start ~U[2026-07-13 09:00:00Z]
  @finish ~U[2026-07-13 09:30:00Z]
  @slot %Interval{start_at: @start, end_at: @finish}
  @meeting %MeetingType{id: "intro", duration_min: 30}
  @resource %Resource{id: "a", timezone: "Etc/UTC"}
  @rule %AvailabilityRule{timezone: "Etc/UTC", windows: []}

  test "interval constructors and validators reject invalid datetime fields" do
    for fields <- [
          %{month: 13},
          %{day: 32},
          %{hour: 25},
          %{minute: nil},
          %{second: -1},
          %{year: "2026"},
          %{microsecond: {1_000_000, 6}},
          %{microsecond: {0, 7}},
          %{microsecond: nil},
          %{utc_offset: nil},
          %{std_offset: 0.0},
          %{time_zone: nil},
          %{zone_abbr: nil},
          %{calendar: nil}
        ] do
      invalid = struct!(@start, fields)
      assert {:error, {:invalid, :interval, :datetime_required}} = Interval.new(invalid, @finish)

      assert {:error, {:invalid, :interval, :datetime_required}} =
               Interval.validate(%{@slot | start_at: invalid})
    end
  end

  test "all time options are checked even when the resource set is empty" do
    invalid = %{@start | month: 13}
    opts = [now: @start, from: @start, until: @finish]

    for key <- [:now, :from, :until] do
      malformed = Keyword.put(opts, key, invalid)

      assert {:error, {:invalid, ^key, ^invalid}} =
               ExBooking.available_slots(@meeting, [], [], malformed)

      assert {:error, {:invalid, ^key, ^invalid}} =
               Availability.assemble(@meeting, [], [], malformed)
    end
  end

  test "invalid schedule times and dates are rejected instead of disappearing" do
    time = %{~T[09:00:00] | hour: 25}
    window = %{weekday: 1, start_time: time, end_time: ~T[10:00:00]}
    rule = %{@rule | windows: [window]}
    assert {:error, {:invalid, :windows, {:weekly, 0, ^window}}} = Schedule.validate(rule)

    assert {:error, {:invalid, :windows, {:weekly, 0, ^window}}} =
             Schedule.expand(rule, @start, @finish)

    override = %{date: %{~D[2026-07-13] | day: 32}, windows: []}

    assert {:error, {:invalid, :overrides, {:entry, 0, ^override}}} =
             Schedule.validate(%{@rule | overrides: [override]})

    override_window = %{start_time: time, end_time: ~T[10:00:00]}

    assert {:error, {:invalid, :overrides, {:window, 0, 0, ^override_window}}} =
             Schedule.validate(%{
               @rule
               | overrides: [%{date: ~D[2026-07-13], windows: [override_window]}]
             })
  end

  test "invalid daily-count dates and fairness datetimes fail preflight" do
    date = %{~D[2026-07-13] | day: 32}
    resource = %{@resource | daily_booking_counts: %{date => 1}}

    assert {:error, {:invalid, :daily_booking_counts, {"a", {^date, 1}}}} =
             Availability.validate_inputs(@meeting, [resource], [@rule])

    invalid = %{@start | month: 13}
    resource = %{@resource | fairness: %{last_assigned_at: invalid}}

    assert {:error, {:invalid, :resource_fairness, {"a", {:last_assigned_at, ^invalid}}}} =
             ExBooking.assign([resource], @slot, strategy: :round_robin)
  end

  test "hold expiry rejects an invalid datetime before emitting an event" do
    hold = %Hold{
      id: "hold",
      slot: @slot,
      resource_ids: ["a"],
      meeting_type_id: "intro",
      expires_at: %{@start | month: 13}
    }

    assert {:error, {:invalid, :hold, {:invalid, :expires_at}}} =
             ExBooking.expire_hold(hold, [])
  end

  test "standalone eligibility checks now before temporal work" do
    request = %Request{meeting_type_id: "intro", invitee_timezone: "Etc/UTC", slot: @slot}
    invalid = %{@start | month: 13}

    assert {:error, {:invalid, :now, ^invalid}} =
             Availability.eligible(request, @meeting, [], [], invalid)
  end

  test "recurrence validates dtstart, horizons and rule UNTIL before expansion" do
    invalid = %{@start | month: 13}

    for {start, from, until} <- [
          {invalid, @start, @finish},
          {@start, invalid, @finish},
          {@start, @start, invalid}
        ] do
      assert {:error, {:invalid, :rrule, :arguments}} =
               RRule.expand("FREQ=DAILY", start, 30, from, until)
    end

    assert {:error, {:invalid, :rrule, :until}} =
             RRule.expand(%RRule{freq: :daily, until: invalid}, @start, 30, @start, @finish)
  end
end
