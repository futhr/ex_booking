defmodule ExBooking.AvailabilityTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  import ExBooking.TestGenerators

  alias ExBooking.Availability
  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Resource

  doctest ExBooking.Availability

  @now ~U[2026-07-08 12:00:00Z]
  @horizon [now: @now, from: ~U[2026-07-13 00:00:00Z], until: ~U[2026-07-13 23:59:59Z]]

  defp rule(overrides \\ []) do
    defaults = %{
      timezone: "Etc/UTC",
      windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}]
    }

    struct!(AvailabilityRule, Map.merge(defaults, Map.new(overrides)))
  end

  defp resource(busy \\ []), do: %Resource{id: "res_1", timezone: "Etc/UTC", busy: busy}

  defp meeting_type(overrides \\ []) do
    struct!(
      MeetingType,
      Map.merge(%{id: "m", duration_min: 30, slot_interval_min: 15}, Map.new(overrides))
    )
  end

  defp busy(start_at, end_at, kind \\ :busy) do
    %Interval{start_at: start_at, end_at: end_at, kind: kind}
  end

  defp starts(slots), do: Enum.map(slots, & &1.start_at)

  describe "assemble/4 (:one)" do
    test "deduplicates identical slots across resources" do
      res_a = %{resource() | id: "a"}
      res_b = %{resource() | id: "b"}

      assert {:ok, slots} =
               Availability.assemble(meeting_type(), [res_a, res_b], [rule(), rule()], @horizon)

      assert slots == Enum.uniq_by(slots, & &1.start_at)
      assert slots == Enum.sort_by(slots, & &1.start_at, DateTime)
    end

    test "buffers block adjacency but not the day edge" do
      rule = rule(buffers: %{before_min: 15, after_min: 0})
      resource = resource([busy(~U[2026-07-13 11:00:00Z], ~U[2026-07-13 12:00:00Z])])

      assert {:ok, slots} = Availability.assemble(meeting_type(), [resource], [rule], @horizon)
      starts = starts(slots)

      assert ~U[2026-07-13 09:00:00Z] in starts
      assert ~U[2026-07-13 10:30:00Z] in starts
      refute ~U[2026-07-13 12:00:00Z] in starts
      assert ~U[2026-07-13 12:15:00Z] in starts
    end

    test "back-to-back bookings with zero buffers are legal" do
      resource = resource([busy(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 10:30:00Z])])

      assert {:ok, slots} = Availability.assemble(meeting_type(), [resource], [rule()], @horizon)
      starts = starts(slots)

      refute ~U[2026-07-13 10:00:00Z] in starts
      assert ~U[2026-07-13 10:30:00Z] in starts
    end

    test "a 30-minute meeting on a 15-minute grid yields three slots in a 60-minute window" do
      rule = rule(windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}])

      assert {:ok, slots} = Availability.assemble(meeting_type(), [resource()], [rule], @horizon)

      assert starts(slots) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-13 09:15:00Z],
               ~U[2026-07-13 09:30:00Z]
             ]
    end
  end

  describe "validate/5" do
    defp request(slot, overrides \\ []) do
      defaults = %{meeting_type_id: "m", invitee_timezone: "Etc/UTC", slot: slot}
      struct!(Request, Map.merge(defaults, Map.new(overrides)))
    end

    test "a free slot validates" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      assert :ok =
               Availability.validate(request(slot), meeting_type(), [resource()], [rule()],
                 now: @now
               )
    end

    test "a conflicting slot reports the conflicting interval" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      conflict = busy(~U[2026-07-13 09:15:00Z], ~U[2026-07-13 09:45:00Z])

      assert {:error, [{:conflict, "res_1", ^conflict}]} =
               Availability.validate(
                 request(slot),
                 meeting_type(),
                 [resource([conflict])],
                 [rule()],
                 now: @now
               )
    end

    test "preferred_resource_ids restricts the candidate pool" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      assert {:error, [{:no_eligible_resource, ^slot}]} =
               Availability.validate(
                 request(slot, preferred_resource_ids: ["missing"]),
                 meeting_type(),
                 [resource()],
                 [rule()],
                 now: @now
               )
    end

    test "a missing slot is rejected" do
      assert {:error, [{:invalid, :slot, :missing}]} =
               Availability.validate(request(nil), meeting_type(), [resource()], [rule()],
                 now: @now
               )
    end

    test "mismatched resources and rules is a malformed input error" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      assert {:error, [{:invalid, :rules, :length_mismatch}]} =
               Availability.validate(request(slot), meeting_type(), [resource()], [], now: @now)
    end
  end

  describe "assemble/4 (:collective)" do
    test "offers only slots where all resources are free" do
      window = rule(windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:30:00]}])
      free = %{resource() | id: "a"}

      partly_busy = %{
        resource([busy(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])])
        | id: "b"
      }

      meeting_type = meeting_type(participants: :collective, slot_interval_min: 30)

      assert {:ok, slots} =
               Availability.assemble(
                 meeting_type,
                 [free, partly_busy],
                 [window, window],
                 @horizon
               )

      starts = starts(slots)
      refute ~U[2026-07-13 09:00:00Z] in starts
      assert ~U[2026-07-13 09:30:00Z] in starts
      assert ~U[2026-07-13 10:00:00Z] in starts
    end
  end

  describe "assemble/4 (:pool)" do
    test "offers a slot only while free seats meet capacity_required" do
      window = rule(windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:30:00]}])
      free = %{resource() | id: "a"}

      partly_busy = %{
        resource([busy(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])])
        | id: "b"
      }

      meeting_type =
        meeting_type(participants: :pool, capacity_required: 2, slot_interval_min: 30)

      assert {:ok, slots} =
               Availability.assemble(
                 meeting_type,
                 [free, partly_busy],
                 [window, window],
                 @horizon
               )

      starts = starts(slots)
      refute ~U[2026-07-13 09:00:00Z] in starts
      assert ~U[2026-07-13 09:30:00Z] in starts
    end
  end

  describe "eligible via validate/5 for multi-party modes" do
    test ":collective requires every resource to be free" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      free = %{resource() | id: "a"}
      busy_res = %{resource([busy(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])]) | id: "b"}
      meeting_type = meeting_type(participants: :collective)

      assert :ok =
               Availability.validate(
                 request(slot),
                 meeting_type,
                 [free, %{free | id: "c"}],
                 [rule(), rule()],
                 now: @now
               )

      assert {:error, [{:conflict, "b", _busy}]} =
               Availability.validate(
                 request(slot),
                 meeting_type,
                 [free, busy_res],
                 [rule(), rule()],
                 now: @now
               )
    end

    test ":pool counts a policy-violating resource as unavailable" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      meeting_type = meeting_type(participants: :pool, capacity_required: 1)
      strict = rule(lead_time_min: 100_000)

      assert {:error, reasons} =
               Availability.validate(request(slot), meeting_type, [resource()], [strict],
                 now: @now
               )

      assert Enum.any?(reasons, &match?({:lead_time, _short}, &1))
    end

    test ":pool needs enough free seats" do
      slot = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      free = %{resource() | id: "a"}
      busy_res = %{resource([busy(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])]) | id: "b"}
      meeting_type = meeting_type(participants: :pool, capacity_required: 2)

      assert :ok =
               Availability.validate(
                 request(slot),
                 meeting_type,
                 [free, %{free | id: "c"}],
                 [rule(), rule()],
                 now: @now
               )

      assert {:error, _reasons} =
               Availability.validate(
                 request(slot),
                 meeting_type,
                 [free, busy_res],
                 [rule(), rule()],
                 now: @now
               )
    end
  end

  property "buffer equivalence: inflating the slot and inflating busy agree" do
    check all(
            slot <- interval(),
            busy <- interval(),
            before_min <- integer(0..120),
            after_min <- integer(0..120)
          ) do
      inflate_slot = Interval.overlaps?(Interval.inflate(slot, before_min, after_min), busy)
      inflate_busy = Interval.overlaps?(slot, Interval.inflate(busy, after_min, before_min))

      assert inflate_slot == inflate_busy
    end
  end
end
