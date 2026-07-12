defmodule ExBooking.DSTFixturesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.Availability
  alias ExBooking.AvailabilityRule
  alias ExBooking.DSTFixtures
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Resource
  alias ExBooking.Schedule

  for zone <- ExBooking.DSTFixtures.zones() do
    describe "#{zone} corpus" do
      test "spring-forward wall time falls in a gap" do
        {date, time, timezone} = DSTFixtures.gap_wall_time(unquote(zone))

        assert {:gap, _, _} = DateTime.new(date, time, timezone)
      end

      test "fall-back wall time is ambiguous" do
        {date, time, timezone} = DSTFixtures.ambiguous_wall_time(unquote(zone))

        assert {:ambiguous, first, second} = DateTime.new(date, time, timezone)
        assert DateTime.compare(first, second) == :lt
      end

      test "wall times outside transitions are unambiguous" do
        %{timezone: timezone, spring_forward: %{date: date}} =
          DSTFixtures.transitions(unquote(zone))

        assert {:ok, %DateTime{}} = DateTime.new(date, ~T[12:00:00], timezone)
      end

      test "requested slots remain contained in fall-back offerability" do
        %{timezone: timezone, fall_back: fall_back} = DSTFixtures.transitions(unquote(zone))

        rule = %AvailabilityRule{
          timezone: timezone,
          windows: [],
          overrides: [
            %{
              date: fall_back.date,
              windows: [
                %{start_time: fall_back.ambiguous_starts, end_time: fall_back.ambiguous_ends}
              ]
            }
          ]
        }

        from = DateTime.new!(Date.add(fall_back.date, -1), ~T[00:00:00], "Etc/UTC")
        until = DateTime.new!(Date.add(fall_back.date, 1), ~T[00:00:00], "Etc/UTC")
        assert {:ok, [offerable]} = Schedule.expand(rule, from, until)

        slot = Interval.new!(offerable.start_at, DateTime.add(offerable.start_at, 30, :minute))
        meeting_type = %MeetingType{id: "dst", duration_min: 30}
        resource = %Resource{id: "host", timezone: timezone}
        request = %Request{meeting_type_id: "dst", invitee_timezone: timezone, slot: slot}

        assert :ok =
                 Availability.validate(request, meeting_type, [resource], [rule],
                   now: DateTime.add(slot.start_at, -1, :day)
                 )
      end
    end
  end
end
