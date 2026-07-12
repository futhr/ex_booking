defmodule ExBooking.AvailabilityInputValidationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Reservation
  alias ExBooking.Resource
  alias ExBooking.Schedule

  @horizon [
    now: ~U[2026-07-08 12:00:00Z],
    from: ~U[2026-07-13 00:00:00Z],
    until: ~U[2026-07-13 23:59:59Z]
  ]

  defp meeting_type(overrides \\ %{}) do
    struct!(MeetingType, Map.merge(%{id: "intro", duration_min: 30}, Map.new(overrides)))
  end

  defp resource(overrides \\ %{}) do
    struct!(Resource, Map.merge(%{id: "host_1", timezone: "Etc/UTC"}, Map.new(overrides)))
  end

  defp rule(overrides \\ %{}) do
    defaults = %{
      timezone: "Etc/UTC",
      windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
    }

    struct!(AvailabilityRule, Map.merge(defaults, Map.new(overrides)))
  end

  describe "availability facade input validation" do
    test "rejects invalid rule and resource timezones without raising" do
      assert {:error, {:invalid, :rule_timezone, "Missing/Timezone"}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource()],
                 [rule(timezone: "Missing/Timezone")],
                 @horizon
               )

      assert {:error, {:invalid, :resource_timezone, {"host_1", "Missing/Timezone"}}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource(timezone: "Missing/Timezone")],
                 [rule()],
                 @horizon
               )
    end

    test "rejects malformed meeting type fields before slot generation" do
      invalid = [
        {%{duration_min: 0}, {:invalid, :duration_min, 0}},
        {%{slot_interval_min: 0}, {:invalid, :slot_interval_min, 0}},
        {%{capacity_required: 0}, {:invalid, :capacity_required, 0}},
        {%{participants: :everyone}, {:invalid, :participants, :everyone}}
      ]

      for {attrs, reason} <- invalid do
        assert {:error, ^reason} =
                 ExBooking.available_slots(meeting_type(attrs), [resource()], [rule()], @horizon)
      end
    end

    test "rejects a malformed resource capacity before pool arithmetic" do
      assert {:error, {:invalid, :resource_capacity, {"host_1", 0}}} =
               ExBooking.available_slots(
                 meeting_type(participants: :pool),
                 [resource(capacity: 0)],
                 [rule()],
                 @horizon
               )
    end

    test "rejects malformed resource and rule containers and entries" do
      assert {:error, {:invalid, :resources, :not_a_list}} =
               ExBooking.available_slots(meeting_type(), :not_a_list, [rule()], @horizon)

      assert {:error, {:invalid, :resources, {:at, 0, :not_a_resource}}} =
               ExBooking.available_slots(meeting_type(), [:not_a_resource], [rule()], @horizon)

      assert {:error, {:invalid, :rules, :not_a_list}} =
               ExBooking.available_slots(meeting_type(), [resource()], :not_a_list, @horizon)

      assert {:error, {:invalid, :rules, {:at, 0, :not_a_rule}}} =
               ExBooking.available_slots(meeting_type(), [resource()], [:not_a_rule], @horizon)

      assert {:error, {:invalid, :resource_timezone, {"host_1", nil}}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource(timezone: nil)],
                 [rule()],
                 @horizon
               )
    end

    test "propagates malformed schedule windows as facade errors" do
      malformed = %{weekday: 1, start_time: "09:00", end_time: ~T[10:00:00]}

      assert {:error, {:invalid, :windows, {:weekly, 0, ^malformed}}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource()],
                 [rule(windows: [malformed])],
                 @horizon
               )
    end

    test "rejects malformed nested resource facts instead of ignoring them" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      assert {:error, {:invalid, :resource_reservations, {"host_1", 0, {:capacity_consumed, 0}}}} =
               ExBooking.available_slots(
                 meeting_type(participants: :pool),
                 [resource(reservations: [%Reservation{interval: slot, capacity_consumed: 0}])],
                 [rule()],
                 @horizon
               )

      assert {:error, {:invalid, :resource_busy, {"host_1", 0, :datetime_required}}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource(busy: [%Interval{start_at: nil, end_at: nil}])],
                 [rule()],
                 @horizon
               )

      assert {:error, {:invalid, :daily_booking_counts, {"host_1", {~D[2026-07-13], -1}}}} =
               ExBooking.available_slots(
                 meeting_type(),
                 [resource(daily_booking_counts: %{~D[2026-07-13] => -1})],
                 [rule()],
                 @horizon
               )
    end

    test "rejects malformed request identity, timezone, preferences, and routing context" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      base = %Request{meeting_type_id: "intro", invitee_timezone: "Etc/UTC", slot: slot}
      opts = [now: @horizon[:now]]

      for {request, reason} <- [
            {%{base | invitee_timezone: "Missing/Timezone"},
             {:invalid, :invitee_timezone, "Missing/Timezone"}},
            {%{base | preferred_resource_ids: [""]}, {:invalid, :preferred_resource_ids, ""}},
            {%{base | routing_context: :opaque}, {:invalid, :routing_context, :opaque}}
          ] do
        assert {:error, ^reason} =
                 ExBooking.validate_request(request, meeting_type(), [resource()], [rule()], opts)
      end
    end

    test "covers every nested container and scalar validation boundary" do
      invalid_interval = %Interval{start_at: nil, end_at: nil}

      invalid_resources = [
        {resource(id: ""), {:invalid, :resource_id, ""}},
        {resource(busy: :busy), {:invalid, :resource_busy, {"host_1", :busy}}},
        {resource(reservations: [:bad]), {:invalid, :resource_reservations, {"host_1", 0, :bad}}},
        {resource(reservations: :bad), {:invalid, :resource_reservations, {"host_1", :bad}}},
        {resource(reservations: [%Reservation{interval: invalid_interval}]),
         {:invalid, :resource_reservations, {"host_1", 0, {:interval, :datetime_required}}}},
        {resource(daily_booking_counts: :bad),
         {:invalid, :daily_booking_counts, {"host_1", :bad}}},
        {resource(fairness: :bad), {:invalid, :resource_fairness, {"host_1", :bad}}},
        {resource(fairness: %{unexpected: 1}),
         {:invalid, :resource_fairness, {"host_1", {:unexpected, 1}}}},
        {resource(fairness: %{assignments_count: -1}),
         {:invalid, :resource_fairness, {"host_1", {:assignments_count, -1}}}},
        {resource(fairness: %{last_assigned_at: :never}),
         {:invalid, :resource_fairness, {"host_1", {:last_assigned_at, :never}}}},
        {resource(fairness: %{weight: 0}),
         {:invalid, :resource_fairness, {"host_1", {:weight, 0}}}},
        {resource(fairness: %{priority: :high}),
         {:invalid, :resource_fairness, {"host_1", {:priority, :high}}}}
      ]

      for {invalid_resource, reason} <- invalid_resources do
        assert {:error, ^reason} =
                 ExBooking.available_slots(meeting_type(), [invalid_resource], [rule()], @horizon)
      end

      assert {:error, {:invalid, :meeting_type_id, ""}} =
               ExBooking.available_slots(meeting_type(id: ""), [resource()], [rule()], @horizon)

      assert {:error, {:invalid, :meeting_buffers, %{before_min: -1, after_min: 0}}} =
               ExBooking.available_slots(
                 meeting_type(buffers: %{before_min: -1, after_min: 0}),
                 [resource()],
                 [rule()],
                 @horizon
               )
    end
  end

  describe "Schedule validation" do
    test "rejects malformed weekly window containers and entries" do
      assert {:error, {:invalid, :windows, {:weekly, :not_a_list, nil}}} =
               Schedule.expand(
                 rule(windows: nil),
                 @horizon[:from],
                 @horizon[:until]
               )

      malformed = %{weekday: 8, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}

      assert {:error, {:invalid, :windows, {:weekly, 0, ^malformed}}} =
               Schedule.expand(
                 rule(windows: [malformed]),
                 @horizon[:from],
                 @horizon[:until]
               )
    end

    test "rejects malformed override entries and override windows" do
      malformed_entry = %{date: "2026-07-13", windows: []}

      assert {:error, {:invalid, :overrides, {:entry, 0, ^malformed_entry}}} =
               Schedule.expand(
                 rule(overrides: [malformed_entry]),
                 @horizon[:from],
                 @horizon[:until]
               )

      malformed_window = %{start_time: ~T[09:00:00], end_time: "10:00"}

      assert {:error, {:invalid, :overrides, {:window, 0, 0, ^malformed_window}}} =
               Schedule.expand(
                 rule(overrides: [%{date: ~D[2026-07-13], windows: [malformed_window]}]),
                 @horizon[:from],
                 @horizon[:until]
               )
    end

    test "rejects non-list overrides and non-binary timezones" do
      assert {:error, {:invalid, :overrides, {:not_a_list, nil}}} =
               Schedule.expand(rule(overrides: nil), @horizon[:from], @horizon[:until])

      assert {:error, {:invalid, :rule_timezone, nil}} =
               Schedule.expand(rule(timezone: nil), @horizon[:from], @horizon[:until])
    end

    test "rejects a non-increasing direct expansion horizon" do
      assert {:error, {:invalid, :horizon, :not_increasing}} =
               Schedule.expand(rule(), @horizon[:until], @horizon[:from])
    end

    test "rejects malformed blackouts and rule policy fields" do
      assert {:error, {:invalid, :blackouts, {0, :datetime_required}}} =
               Schedule.validate(rule(blackouts: [%Interval{start_at: nil, end_at: nil}]))

      assert {:error, {:invalid, :lead_time_min, -1}} =
               Schedule.validate(rule(lead_time_min: -1))

      assert {:error, {:invalid, :booking_window_days, 0}} =
               Schedule.validate(rule(booking_window_days: 0))

      assert {:error, {:invalid, :rule_buffers, %{before_min: -1, after_min: 0}}} =
               Schedule.validate(rule(buffers: %{before_min: -1, after_min: 0}))

      assert {:error, {:invalid, :blackouts, :bad}} = Schedule.validate(rule(blackouts: :bad))
      assert :ok = Schedule.validate(rule(booking_window_days: 1, max_per_day: 1))
    end
  end
end
