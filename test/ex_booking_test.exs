defmodule ExBookingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExBooking.TestBuilders

  alias ExBooking.Interval

  doctest ExBooking
  doctest ExBooking.AvailabilityRule
  doctest ExBooking.Decision
  doctest ExBooking.Event
  doctest ExBooking.Hold
  doctest ExBooking.MeetingType
  doctest ExBooking.Request
  doctest ExBooking.Reservation
  doctest ExBooking.Resource

  @now ~U[2026-07-08 12:00:00Z]
  @horizon [now: @now, from: ~U[2026-07-13 00:00:00Z], until: ~U[2026-07-17 23:59:59Z]]

  describe "option validation" do
    test "available_slots/4 requires a complete horizon" do
      assert {:error, {:invalid, :horizon, :requires_from_and_until}} =
               ExBooking.available_slots(build(:meeting_type), [], [], now: @now)
    end

    test "horizons must be increasing and optional horizons must be paired" do
      assert {:error, {:invalid, :horizon, :not_increasing}} =
               ExBooking.available_slots(build(:meeting_type), [], [],
                 now: @now,
                 from: ~U[2026-07-14 00:00:00Z],
                 until: ~U[2026-07-13 00:00:00Z]
               )

      assert {:error, {:invalid, :horizon, :requires_from_and_until}} =
               ExBooking.decide(build(:request), build(:meeting_type), [], [],
                 now: @now,
                 from: ~U[2026-07-13 00:00:00Z]
               )
    end

    test "unknown options are rejected" do
      assert {:error, {:invalid, :opts, message}} =
               ExBooking.available_slots(build(:meeting_type), [], [], [bogus: 1] ++ @horizon)

      assert message =~ "bogus"
    end

    test "invalid alignment options are rejected" do
      assert {:error, {:invalid, :opts, message}} =
               ExBooking.available_slots(
                 build(:meeting_type),
                 [],
                 [],
                 [align: :local] ++ @horizon
               )

      assert message =~ ":align"
    end

    test "decide/5 validates :scorer arity" do
      assert {:error, {:invalid, :opts, _}} =
               ExBooking.decide(build(:request), build(:meeting_type), [], [],
                 now: @now,
                 scorer: fn _ -> 1 end
               )
    end

    test "entry points reject options that have no meaning for them" do
      hold = %ExBooking.Hold{
        id: "hold_1",
        slot: build(:interval),
        resource_ids: ["res_1"],
        meeting_type_id: "demo_30",
        expires_at: ~U[2026-07-13 08:55:00Z]
      }

      assert {:error, {:invalid, :opts, validation_message}} =
               ExBooking.validate_request(build(:request), build(:meeting_type), [], [],
                 now: @now,
                 hold: hold
               )

      assert validation_message =~ ":hold"

      assert {:error, {:invalid, :opts, decision_message}} =
               ExBooking.decide(build(:request), build(:meeting_type), [], [],
                 now: @now,
                 release_hold_id: "hold_1"
               )

      assert decision_message =~ ":release_hold_id"

      assert {:error, {:invalid, :opts, reschedule_message}} =
               ExBooking.reschedule(
                 build(:interval),
                 build(:request),
                 build(:meeting_type),
                 [],
                 [],
                 now: @now,
                 hold: hold
               )

      assert reschedule_message =~ ":hold"
    end
  end

  describe "available_slots/4" do
    test "returns bookable slots sorted ascending by start" do
      assert {:ok, slots} =
               ExBooking.available_slots(
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 @horizon
               )

      refute slots == []
      assert slots == Enum.sort_by(slots, & &1.start_at, DateTime)
      assert Enum.all?(slots, &match?(%Interval{kind: :available}, &1))
    end

    test "empty resources yield no slots" do
      assert {:ok, []} =
               ExBooking.available_slots(build(:meeting_type), [], [], @horizon)
    end

    test "mismatched resources/rules is a malformed input error" do
      assert {:error, {:invalid, :rules, :length_mismatch}} =
               ExBooking.available_slots(
                 build(:meeting_type),
                 [build(:resource)],
                 [],
                 @horizon
               )
    end

    test "clock alignment reaches the slotting pipeline" do
      rule =
        build(:rule,
          timezone: "Etc/UTC",
          windows: [%{weekday: 1, start_time: ~T[09:07:00], end_time: ~T[10:00:00]}]
        )

      resource = build(:resource, timezone: "Etc/UTC")

      assert {:ok, slots} =
               ExBooking.available_slots(
                 build(:meeting_type),
                 [resource],
                 [rule],
                 now: @now,
                 from: ~U[2026-07-13 09:00:00Z],
                 until: ~U[2026-07-13 10:00:00Z],
                 align: :clock
               )

      assert Enum.map(slots, & &1.start_at) == [
               ~U[2026-07-13 09:15:00Z],
               ~U[2026-07-13 09:30:00Z]
             ]
    end
  end

  describe "validate_request/5" do
    test "a free requested slot validates" do
      request = build(:request, slot: monday_slot(~T[09:00:00]))

      assert :ok =
               ExBooking.validate_request(
                 request,
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )
    end

    test "a conflicting slot returns the conflict reason" do
      busy = %Interval{
        start_at: ~U[2026-07-13 07:00:00Z],
        end_at: ~U[2026-07-13 07:30:00Z],
        kind: :busy
      }

      request = build(:request, slot: monday_slot(~T[09:00:00]))

      assert {:error, reasons} =
               ExBooking.validate_request(
                 request,
                 build(:meeting_type),
                 [build(:resource, busy: [busy])],
                 [build(:rule)],
                 now: @now
               )

      assert Enum.any?(reasons, &match?({:conflict, "res_1", _}, &1))
    end

    test "a request without a slot is rejected" do
      request = build(:request, slot: nil)

      assert {:error, {:invalid, :slot, :required}} =
               ExBooking.validate_request(
                 request,
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )
    end

    test "request identity and exact elapsed duration are structural invariants" do
      slot = build(:interval, end_at: ~U[2026-07-13 09:45:00Z])

      assert {:error, {:invalid, :meeting_type_id, {:mismatch, "other", "demo_30"}}} =
               ExBooking.validate_request(
                 build(:request, meeting_type_id: "other", slot: monday_slot(~T[09:00:00])),
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )

      assert {:error, {:invalid, :slot_duration, {:expected, 1800, :actual, 2700}}} =
               ExBooking.validate_request(
                 build(:request, slot: slot),
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )
    end

    test "exact duration rejects subsecond overflow" do
      start_at = ~U[2026-07-13 09:00:00.000000Z]
      end_at = DateTime.add(start_at, 1_800_000_001, :microsecond)
      slot = build(:interval, start_at: start_at, end_at: end_at)

      assert {:error, {:invalid, :slot_duration, {:expected, 1800, :actual, actual_seconds}}} =
               ExBooking.validate_request(
                 build(:request, slot: slot),
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )

      assert_in_delta actual_seconds, 1800.000001, 0.0000001
    end
  end

  describe "decide/5" do
    setup do
      %{request: build(:request, slot: monday_slot(~T[09:00:00]))}
    end

    test "confirms a valid request with an assigned resource and events", %{request: request} do
      assert {:ok, decision} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now
               )

      assert decision.status == :ok
      assert decision.resource_ids == ["res_1"]
      assert [%ExBooking.Event{type: :booking_confirmed}] = decision.events

      assert [
               {:calendar_event, :create, _},
               {:notify, :booking_confirmation, _},
               {:emit, %ExBooking.Event{}}
             ] =
               decision.intents
    end

    test "a pool decision exposes exact seat consumption on one capable resource", %{
      request: request
    } do
      meeting_type = build(:meeting_type, participants: :pool, capacity_required: 5)
      resource = build(:resource, capacity: 10)

      assert {:ok, decision} =
               ExBooking.decide(request, meeting_type, [resource], [build(:rule)], now: @now)

      assert decision.status == :ok
      assert decision.resource_ids == ["res_1"]
      assert decision.seat_allocations == [%{resource_id: "res_1", capacity_consumed: 5}]
      assert decision.meeting_type_id == "demo_30"
    end

    test "returns a :conflict decision when the slot is busy", %{request: request} do
      busy = %Interval{
        start_at: ~U[2026-07-13 07:00:00Z],
        end_at: ~U[2026-07-13 07:30:00Z],
        kind: :busy
      }

      assert {:ok, decision} =
               ExBooking.decide(
                 request,
                 build(:meeting_type),
                 [build(:resource, busy: [busy])],
                 [build(:rule)],
                 now: @now
               )

      assert decision.status == :conflict
      assert Enum.any?(decision.reasons, &match?({:conflict, "res_1", _}, &1))
    end

    test "returns nearest alternatives when a rejected decision has a horizon", %{
      request: request
    } do
      busy = %Interval{
        start_at: ~U[2026-07-13 07:00:00Z],
        end_at: ~U[2026-07-13 07:30:00Z],
        kind: :busy
      }

      assert {:ok, decision} =
               ExBooking.decide(
                 request,
                 build(:meeting_type),
                 [build(:resource, busy: [busy])],
                 [build(:rule)],
                 now: @now,
                 from: ~U[2026-07-13 00:00:00Z],
                 until: ~U[2026-07-13 23:59:59Z],
                 alternatives_limit: 2
               )

      assert decision.status == :conflict

      assert Enum.map(decision.alternatives, & &1.start_at) == [
               ~U[2026-07-13 07:30:00Z],
               ~U[2026-07-13 07:45:00Z]
             ]
    end

    test "keeps alternatives empty when no alternatives horizon is supplied", %{request: request} do
      busy = %Interval{
        start_at: ~U[2026-07-13 07:00:00Z],
        end_at: ~U[2026-07-13 07:30:00Z],
        kind: :busy
      }

      assert {:ok, decision} =
               ExBooking.decide(
                 request,
                 build(:meeting_type),
                 [build(:resource, busy: [busy])],
                 [build(:rule)],
                 now: @now
               )

      assert decision.alternatives == []
    end

    test "returns a :policy_reject decision when lead time is not met", %{request: request} do
      assert {:ok, decision} =
               ExBooking.decide(
                 request,
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule, lead_time_min: 100_000)],
                 now: @now
               )

      assert decision.status == :policy_reject
      assert Enum.any?(decision.reasons, &match?({:lead_time, _}, &1))
    end

    test "returns a :needs_routing decision when no resource is eligible", %{request: request} do
      assert {:ok, decision} = ExBooking.decide(request, build(:meeting_type), [], [], now: @now)

      assert decision.status == :needs_routing
    end

    test "returns malformed rule pairing directly instead of building a decision", %{
      request: request
    } do
      assert {:error, {:invalid, :rules, :length_mismatch}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [], now: @now)
    end

    test "produces a reserve decision when a hold is supplied", %{request: request} do
      hold = %ExBooking.Hold{
        id: "h1",
        slot: request.slot,
        resource_ids: ["res_1"],
        meeting_type_id: "demo_30",
        expires_at: ~U[2026-07-13 08:00:00Z]
      }

      assert {:ok, decision} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: hold
               )

      assert decision.status == :ok
      assert [%ExBooking.Event{type: :booking_reserved}] = decision.events
      assert [{:reserve, ^hold}, {:emit, _}] = decision.intents
    end

    test "rejects a supplied hold that differs from the canonical decision", %{request: request} do
      hold = %ExBooking.Hold{
        id: "h1",
        slot: request.slot,
        resource_ids: ["wrong"],
        meeting_type_id: "demo_30",
        expires_at: ~U[2026-07-13 08:00:00Z]
      }

      assert {:error, {:invalid, :hold, {:mismatch, :resource_ids}}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: hold
               )

      assert {:error, {:invalid, :hold, {:mismatch, :slot}}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: %{hold | resource_ids: ["res_1"], slot: monday_slot(~T[10:00:00])}
               )

      assert {:error, {:invalid, :hold, {:mismatch, :meeting_type_id}}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: %{hold | resource_ids: ["res_1"], meeting_type_id: "other"}
               )

      assert {:error, {:invalid, :hold, {:invalid, :id}}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: %{hold | id: "", resource_ids: ["res_1"]}
               )

      assert {:error, {:invalid, :hold, {:invalid, :expires_at}}} =
               ExBooking.decide(request, build(:meeting_type), [build(:resource)], [build(:rule)],
                 now: @now,
                 hold: %{hold | expires_at: nil, resource_ids: ["res_1"]}
               )
    end
  end

  describe "cancel/3" do
    @existing build(:interval,
                start_at: ~U[2026-07-13 09:00:00Z],
                end_at: ~U[2026-07-13 09:30:00Z]
              )

    test "emits cancellation event and intents when policy allows it" do
      meeting_type =
        build(:meeting_type, cancellation_policy: %{min_notice_min: 60, allowed: true})

      assert {:ok, decision} =
               ExBooking.cancel(@existing, meeting_type,
                 now: ~U[2026-07-13 07:00:00Z],
                 resource_ids: ["res_1"],
                 routing_context: %{"utm_campaign" => "demo"},
                 release_hold_id: "hold_1"
               )

      assert decision.status == :ok

      assert [
               %ExBooking.Event{
                 type: :booking_canceled,
                 routing_context: %{"utm_campaign" => "demo"}
               }
             ] = decision.events

      assert [
               {:release, "hold_1"},
               {:calendar_event, :cancel, %{resource_ids: ["res_1"]}},
               {:notify, :booking_canceled, %{resource_ids: ["res_1"]}},
               {:emit, %ExBooking.Event{type: :booking_canceled}}
             ] = decision.intents
    end

    test "returns policy rejection when cancellation is blocked" do
      meeting_type =
        build(:meeting_type, cancellation_policy: %{min_notice_min: 0, allowed: false})

      assert {:ok, decision} =
               ExBooking.cancel(@existing, meeting_type, now: ~U[2026-07-13 07:00:00Z])

      assert decision.status == :policy_reject
      assert decision.reasons == [{:policy, :cancellation, :not_allowed}]
    end
  end

  describe "expire_hold/2" do
    test "emits expiry event and release intent for the supplied hold" do
      hold = %ExBooking.Hold{
        id: "hold_1",
        slot: build(:interval),
        resource_ids: ["res_1"],
        meeting_type_id: "demo_30",
        expires_at: ~U[2026-07-13 08:55:00Z]
      }

      assert {:ok, decision} =
               ExBooking.expire_hold(hold, routing_context: %{source: :worker})

      assert decision.status == :ok

      assert [
               %ExBooking.Event{
                 type: :booking_expired,
                 data: %{hold_id: "hold_1", expires_at: ~U[2026-07-13 08:55:00Z]},
                 routing_context: %{source: :worker}
               }
             ] = decision.events

      assert [{:release, "hold_1"}, {:emit, %ExBooking.Event{type: :booking_expired}}] =
               decision.intents
    end
  end

  describe "mark_no_show/3" do
    test "emits no-show event without performing side effects" do
      assert {:ok, decision} =
               ExBooking.mark_no_show(build(:interval), build(:meeting_type),
                 resource_ids: ["res_1"]
               )

      assert decision.status == :ok
      assert [%ExBooking.Event{type: :booking_no_show}] = decision.events
      assert [{:emit, %ExBooking.Event{type: :booking_no_show}}] = decision.intents
    end
  end

  describe "assign/3" do
    test "returns the winning resource for a free pool" do
      assert {:ok, [%ExBooking.Resource{id: "res_1"}]} =
               ExBooking.assign([build(:resource)], build(:interval), strategy: :round_robin)
    end

    test "an empty pool has no eligible resource" do
      assert {:error, :no_eligible_resource} =
               ExBooking.assign([], build(:interval), strategy: :round_robin)
    end

    test "pool assignment consumes capacity rather than counting resources" do
      resources = [build(:resource, id: "a", capacity: 2), build(:resource, id: "b", capacity: 3)]

      assert {:ok, [%ExBooking.Resource{id: "a"}, %ExBooking.Resource{id: "b"}]} =
               ExBooking.assign(resources, build(:interval),
                 participants: :pool,
                 capacity_required: 5
               )

      assert {:error, :no_eligible_resource} =
               ExBooking.assign(resources, build(:interval),
                 participants: :pool,
                 capacity_required: 6
               )

      assert {:ok, [%ExBooking.Resource{id: "b"}]} =
               ExBooking.assign(
                 [build(:resource, id: "a", capacity: 0), build(:resource, id: "b", capacity: 3)],
                 build(:interval),
                 participants: :pool,
                 capacity_required: 3
               )
    end
  end

  describe "evaluate_cancellation/3" do
    @existing build(:interval,
                start_at: ~U[2026-07-13 09:00:00Z],
                end_at: ~U[2026-07-13 09:30:00Z]
              )

    test "allowed when notice is sufficient" do
      meeting_type =
        build(:meeting_type, cancellation_policy: %{min_notice_min: 60, allowed: true})

      assert {:ok, %{allowed?: true, reason: nil}} =
               ExBooking.evaluate_cancellation(@existing, meeting_type,
                 now: ~U[2026-07-13 07:00:00Z]
               )
    end

    test "blocked when too close to the start" do
      meeting_type =
        build(:meeting_type, cancellation_policy: %{min_notice_min: 120, allowed: true})

      assert {:ok, %{allowed?: false, reason: :min_notice}} =
               ExBooking.evaluate_cancellation(@existing, meeting_type,
                 now: ~U[2026-07-13 08:00:00Z]
               )
    end

    test "no policy means cancellation is allowed" do
      assert {:ok, %{allowed?: true, reason: nil}} =
               ExBooking.evaluate_cancellation(@existing, build(:meeting_type),
                 now: ~U[2026-07-13 08:00:00Z]
               )
    end
  end

  describe "reschedule/6" do
    test "reschedules to a new slot with :booking_rescheduled semantics" do
      request = build(:request, slot: monday_slot(~T[10:00:00]))
      meeting_type = build(:meeting_type, reschedule_policy: %{min_notice_min: 60, allowed: true})

      assert {:ok, decision} =
               ExBooking.reschedule(
                 monday_slot(~T[08:00:00]),
                 request,
                 meeting_type,
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )

      assert decision.status == :ok

      assert [%ExBooking.Event{type: :booking_rescheduled, data: %{from: _, to: _}}] =
               decision.events

      assert Enum.any?(decision.intents, &match?({:calendar_event, :move, _}, &1))
    end

    test "release_hold_id prepends a :release intent" do
      request = build(:request, slot: monday_slot(~T[10:00:00]))
      meeting_type = build(:meeting_type, reschedule_policy: %{min_notice_min: 60, allowed: true})

      assert {:ok, decision} =
               ExBooking.reschedule(
                 monday_slot(~T[08:00:00]),
                 request,
                 meeting_type,
                 [build(:resource)],
                 [build(:rule)],
                 now: @now,
                 release_hold_id: "old_hold"
               )

      assert [{:release, "old_hold"} | _] = decision.intents
    end

    test "a blocked reschedule policy yields :policy_reject" do
      request = build(:request, slot: monday_slot(~T[10:00:00]))
      meeting_type = build(:meeting_type, reschedule_policy: %{min_notice_min: 0, allowed: false})

      assert {:ok, decision} =
               ExBooking.reschedule(
                 monday_slot(~T[08:00:00]),
                 request,
                 meeting_type,
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )

      assert decision.status == :policy_reject
      assert [{:policy, :reschedule, :not_allowed}] = decision.reasons
    end

    test "does not erase an unrelated busy interval that overlaps the old slot" do
      existing = monday_slot(~T[08:00:00])
      request = build(:request, slot: monday_slot(~T[08:15:00]))
      unrelated = %{existing | end_at: ~U[2026-07-13 09:00:00Z]}

      resource = build(:resource, busy: [unrelated])
      meeting_type = build(:meeting_type, reschedule_policy: %{min_notice_min: 0, allowed: true})

      assert {:ok, %ExBooking.Decision{status: :conflict}} =
               ExBooking.reschedule(
                 existing,
                 request,
                 meeting_type,
                 [resource],
                 [build(:rule)],
                 now: @now
               )
    end
  end

  describe "lifecycle input validation" do
    test "lifecycle entry points reject malformed temporal and policy input" do
      invalid = %Interval{
        start_at: ~U[2026-07-13 10:00:00Z],
        end_at: ~U[2026-07-13 09:00:00Z]
      }

      malformed_policy = build(:meeting_type, cancellation_policy: %{allowed: true})

      assert {:error, {:invalid, :existing, :empty_or_reversed}} =
               ExBooking.mark_no_show(invalid, build(:meeting_type), [])

      assert {:error, {:invalid, :cancellation_policy, %{allowed: true}}} =
               ExBooking.evaluate_cancellation(build(:interval), malformed_policy, now: @now)
    end

    test "hold expiry rejects malformed hold fields before emitting events" do
      hold = %ExBooking.Hold{
        id: "hold_1",
        slot: %Interval{start_at: nil, end_at: nil},
        resource_ids: ["res_1"],
        meeting_type_id: "demo_30",
        expires_at: ~U[2026-07-13 08:55:00Z]
      }

      assert {:error, {:invalid, :hold, {:invalid, :slot, :datetime_required}}} =
               ExBooking.expire_hold(hold, [])

      assert {:error, {:invalid, :hold, {:invalid, :resource_ids}}} =
               ExBooking.expire_hold(%{hold | slot: build(:interval), resource_ids: [""]}, [])
    end
  end

  describe "struct contracts" do
    test "enforced keys raise on construction" do
      assert_raise ArgumentError, fn -> struct!(ExBooking.MeetingType, id: "x") end
      assert_raise ArgumentError, fn -> struct!(ExBooking.Resource, id: "x") end
      assert_raise ArgumentError, fn -> struct!(ExBooking.Request, meeting_type_id: "x") end
    end

    test "meeting type defaults are stable" do
      meeting_type = build(:meeting_type, slot_interval_min: nil)

      assert meeting_type.capacity_required == 1
      assert meeting_type.participants == :one
      assert meeting_type.slot_interval_min == nil
    end

    test "availability rule defaults are stable" do
      rule = build(:rule)

      assert rule.lead_time_min == 0
      assert rule.buffers == %{before_min: 0, after_min: 0}
      assert rule.overrides == [] and rule.blackouts == []
    end
  end

  defp monday_slot(time) do
    {:ok, start_at} = DateTime.new(~D[2026-07-13], time, "Europe/Stockholm")
    start_utc = DateTime.shift_zone!(start_at, "Etc/UTC")
    Interval.new!(start_utc, DateTime.add(start_utc, 30, :minute))
  end
end
