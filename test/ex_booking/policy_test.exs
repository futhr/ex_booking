defmodule ExBooking.PolicyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.Policy
  alias ExBooking.Resource

  doctest ExBooking.Policy

  @now ~U[2026-07-13 08:00:00Z]

  defp rule(overrides) do
    struct!(AvailabilityRule, Map.merge(%{timezone: "Etc/UTC", windows: []}, Map.new(overrides)))
  end

  defp resource(daily_booking_counts \\ %{}) do
    %Resource{
      id: "res_1",
      timezone: "Etc/UTC",
      daily_booking_counts: daily_booking_counts
    }
  end

  defp slot(start_at) do
    Interval.new!(start_at, DateTime.add(start_at, 30, :minute))
  end

  describe "lead time" do
    test "no violation when the slot starts at or after now + lead time" do
      assert Policy.violations(
               slot(~U[2026-07-13 10:00:00Z]),
               rule(lead_time_min: 60),
               resource(),
               @now
             ) == []
    end

    test "violation reports whole minutes short (rounded up)" do
      assert [{:lead_time, 30}] =
               Policy.violations(
                 slot(~U[2026-07-13 09:30:00Z]),
                 rule(lead_time_min: 120),
                 resource(),
                 @now
               )
    end

    test "a slot exactly at the lead-time boundary is allowed" do
      assert Policy.violations(
               slot(~U[2026-07-13 09:00:00Z]),
               rule(lead_time_min: 60),
               resource(),
               @now
             ) == []
    end
  end

  describe "booking window" do
    test "nil booking window is unbounded" do
      far = slot(~U[2027-01-01 10:00:00Z])
      assert Policy.violations(far, rule(booking_window_days: nil), resource(), @now) == []
    end

    test "a slot within the window is allowed" do
      assert Policy.violations(
               slot(~U[2026-07-15 10:00:00Z]),
               rule(booking_window_days: 7),
               resource(),
               @now
             ) == []
    end

    test "a slot past the last bookable date is outside the window" do
      slot = slot(~U[2026-07-16 10:00:00Z])

      assert [{:outside_window, ~D[2026-07-16]}] =
               Policy.violations(slot, rule(booking_window_days: 2), resource(), @now)
    end
  end

  describe "daily cap" do
    test "nil cap is uncapped" do
      assert Policy.violations(
               slot(~U[2026-07-13 10:00:00Z]),
               rule(max_per_day: nil),
               resource(),
               @now
             ) == []
    end

    test "under the cap is allowed" do
      assert Policy.violations(
               slot(~U[2026-07-13 11:00:00Z]),
               rule(max_per_day: 2),
               resource(%{~D[2026-07-13] => 1}),
               @now
             ) == []
    end

    test "at the cap is rejected" do
      assert [{:daily_cap, "res_1", ~D[2026-07-13]}] =
               Policy.violations(
                 slot(~U[2026-07-13 11:00:00Z]),
                 rule(max_per_day: 2),
                 resource(%{~D[2026-07-13] => 2}),
                 @now
               )
    end

    test "generic calendar busy intervals do not become booking counts" do
      resource = %{
        resource()
        | busy: [
            %Interval{
              start_at: ~U[2026-07-13 09:00:00Z],
              end_at: ~U[2026-07-13 09:30:00Z],
              kind: :busy
            }
          ]
      }

      assert Policy.violations(
               slot(~U[2026-07-13 11:00:00Z]),
               rule(max_per_day: 1),
               resource,
               @now
             ) == []
    end

    test "counts use the slot date in the rule timezone" do
      stockholm_rule =
        rule(timezone: "Europe/Stockholm", max_per_day: 1)

      assert [{:daily_cap, "res_1", ~D[2026-07-14]}] =
               Policy.violations(
                 slot(~U[2026-07-13 22:30:00Z]),
                 stockholm_rule,
                 resource(%{~D[2026-07-14] => 1}),
                 @now
               )
    end
  end

  describe "notice_ok/3 (cancellation / reschedule)" do
    @existing Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

    test "nil policy is always allowed" do
      assert Policy.notice_ok(@existing, nil, ~U[2026-07-13 08:59:00Z]) == :ok
    end

    test "a policy that forbids the action is not allowed" do
      policy = %{min_notice_min: 0, allowed: false}

      assert Policy.notice_ok(@existing, policy, ~U[2026-07-10 09:00:00Z]) ==
               {:error, :not_allowed}
    end

    test "sufficient notice is allowed" do
      policy = %{min_notice_min: 60, allowed: true}
      assert Policy.notice_ok(@existing, policy, ~U[2026-07-13 07:00:00Z]) == :ok
    end

    test "insufficient notice is rejected" do
      policy = %{min_notice_min: 120, allowed: true}

      assert Policy.notice_ok(@existing, policy, ~U[2026-07-13 08:00:00Z]) ==
               {:error, :min_notice}
    end
  end

  test "violations accumulate across policies" do
    rule = rule(lead_time_min: 26 * 60, booking_window_days: 0)
    reasons = Policy.violations(slot(~U[2026-07-14 09:00:00Z]), rule, resource(), @now)

    assert Enum.any?(reasons, &match?({:lead_time, _}, &1))
    assert Enum.any?(reasons, &match?({:outside_window, _}, &1))
  end
end
