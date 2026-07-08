defmodule ExBookingTest do
  use ExUnit.Case, async: true

  import ExBooking.TestBuilders

  alias ExBooking.Interval

  @now ~U[2026-07-08 12:00:00Z]
  # 2026-07-13 is a Monday; the default rule offers Mon–Fri.
  @horizon [now: @now, from: ~U[2026-07-13 00:00:00Z], until: ~U[2026-07-17 23:59:59Z]]

  describe "option validation" do
    test "available_slots/4 requires :now, :from, :until" do
      assert {:error, {:invalid, :opts, message}} =
               ExBooking.available_slots(build(:meeting_type), [], [], now: @now)

      assert message =~ ":from"
    end

    test "unknown options are rejected" do
      assert {:error, {:invalid, :opts, message}} =
               ExBooking.available_slots(build(:meeting_type), [], [], [bogus: 1] ++ @horizon)

      assert message =~ "bogus"
    end

    test "decide/5 validates :scorer arity" do
      assert {:error, {:invalid, :opts, _message}} =
               ExBooking.decide(build(:request), build(:meeting_type), [], [],
                 now: @now,
                 scorer: fn _resource -> 1 end
               )
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

      assert {:error, [{:invalid, :slot, :missing}]} =
               ExBooking.validate_request(
                 request,
                 build(:meeting_type),
                 [build(:resource)],
                 [build(:rule)],
                 now: @now
               )
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

      assert [{:calendar_event, :create, _payload}, {:emit, %ExBooking.Event{}}] =
               decision.intents
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
      assert [{:reserve, ^hold}, {:emit, _event}] = decision.intents
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

      assert [%ExBooking.Event{type: :booking_rescheduled, data: %{from: _from, to: _to}}] =
               decision.events

      assert Enum.any?(decision.intents, &match?({:calendar_event, :move, _payload}, &1))
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

      assert [{:release, "old_hold"} | _rest] = decision.intents
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
  end

  describe "struct contracts" do
    test "enforced keys raise on construction" do
      assert_raise ArgumentError, fn -> struct!(ExBooking.MeetingType, id: "x") end
      assert_raise ArgumentError, fn -> struct!(ExBooking.Resource, id: "x") end
      assert_raise ArgumentError, fn -> struct!(ExBooking.Request, meeting_type_id: "x") end
    end

    test "meeting type defaults follow SP.01" do
      meeting_type = build(:meeting_type, slot_interval_min: nil)

      assert meeting_type.capacity_required == 1
      assert meeting_type.participants == :one
      assert meeting_type.slot_interval_min == nil
    end

    test "availability rule defaults follow SP.01" do
      rule = build(:rule)

      assert rule.lead_time_min == 0
      assert rule.buffers == %{before_min: 0, after_min: 0}
      assert rule.overrides == [] and rule.blackouts == []
    end
  end

  # A slot at a wall time on Monday 2026-07-13 in the rule timezone
  # (Europe/Stockholm, CEST = UTC+2).
  defp monday_slot(time) do
    {:ok, start_at} = DateTime.new(~D[2026-07-13], time, "Europe/Stockholm")
    start_utc = DateTime.shift_zone!(start_at, "Etc/UTC")
    Interval.new!(start_utc, DateTime.add(start_utc, 30, :minute))
  end
end
