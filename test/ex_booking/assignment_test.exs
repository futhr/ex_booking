defmodule ExBooking.AssignmentTest do
  use ExUnit.Case, async: true

  alias ExBooking.Assignment
  alias ExBooking.Interval
  alias ExBooking.Resource

  doctest ExBooking.Assignment

  @slot Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

  defp resource(id, fairness \\ nil) do
    %Resource{id: id, timezone: "Etc/UTC", fairness: fairness}
  end

  defp fairness(overrides) do
    Map.merge(
      %{assignments_count: 0, last_assigned_at: nil, weight: 1.0, priority: 0},
      Map.new(overrides)
    )
  end

  defp winner(resources, opts), do: Assignment.assign(resources, @slot, opts)

  test "an empty pool has no eligible resource" do
    assert {:error, :no_eligible_resource} = winner([], strategy: :first_available)
  end

  describe ":first_available" do
    test "picks the lowest resource id" do
      assert {:ok, [%Resource{id: "a"}]} =
               winner([resource("c"), resource("a"), resource("b")], strategy: :first_available)
    end
  end

  describe ":round_robin" do
    test "picks the lowest assignments_count, tie-broken by id" do
      resources = [
        resource("a", fairness(assignments_count: 5)),
        resource("b", fairness(assignments_count: 2)),
        resource("c", fairness(assignments_count: 2))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :round_robin)
    end

    test "missing fairness ranks last" do
      resources = [resource("a"), resource("b", fairness(assignments_count: 9))]
      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :round_robin)
    end
  end

  describe ":least_recently_booked" do
    test "never-assigned (nil) ranks first" do
      resources = [
        resource("a", fairness(last_assigned_at: ~U[2026-07-01 09:00:00Z])),
        resource("b", fairness(last_assigned_at: nil))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :least_recently_booked)
    end

    test "otherwise the earliest last_assigned_at wins" do
      resources = [
        resource("a", fairness(last_assigned_at: ~U[2026-07-05 09:00:00Z])),
        resource("b", fairness(last_assigned_at: ~U[2026-07-01 09:00:00Z]))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :least_recently_booked)
    end
  end

  describe ":weighted" do
    test "picks the lowest assignments_count / weight ratio" do
      resources = [
        resource("a", fairness(assignments_count: 4, weight: 1.0)),
        resource("b", fairness(assignments_count: 6, weight: 3.0))
      ]

      # a: 4/1 = 4.0; b: 6/3 = 2.0 → b wins.
      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :weighted)
    end
  end

  describe ":priority" do
    test "highest priority wins" do
      resources = [
        resource("a", fairness(priority: 1)),
        resource("b", fairness(priority: 5))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :priority)
    end

    test "ties fall back to round-robin" do
      resources = [
        resource("a", fairness(priority: 5, assignments_count: 3)),
        resource("b", fairness(priority: 5, assignments_count: 1))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :priority)
    end
  end

  describe ":owner_first" do
    test "the owner wins when present" do
      resources = [resource("a", fairness(assignments_count: 0)), resource("owner")]

      assert {:ok, [%Resource{id: "owner"}]} =
               winner(resources, strategy: {:owner_first, owner_id: "owner"})
    end

    test "falls back to the configured strategy when the owner is absent" do
      resources = [
        resource("a", fairness(assignments_count: 5)),
        resource("b", fairness(assignments_count: 1))
      ]

      assert {:ok, [%Resource{id: "b"}]} =
               winner(resources,
                 strategy: {:owner_first, owner_id: "owner", fallback: :round_robin}
               )
    end
  end

  describe "fairness edge cases" do
    test ":weighted and :priority rank resources without fairness last" do
      with_fairness = resource("a", fairness(assignments_count: 1, weight: 1.0, priority: 3))
      without = resource("z")

      assert {:ok, [%Resource{id: "a"}]} = winner([without, with_fairness], strategy: :weighted)
      assert {:ok, [%Resource{id: "a"}]} = winner([without, with_fairness], strategy: :priority)
    end

    test "a {strategy, opts} tuple selects that strategy" do
      resources = [
        resource("a", fairness(assignments_count: 5)),
        resource("b", fairness(assignments_count: 1))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: {:round_robin, []})
    end

    test "round-robin ties break by earliest last_assigned_at" do
      resources = [
        resource("a", fairness(assignments_count: 2, last_assigned_at: ~U[2026-07-05 09:00:00Z])),
        resource("b", fairness(assignments_count: 2, last_assigned_at: ~U[2026-07-01 09:00:00Z]))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :round_robin)
    end
  end

  describe "scoring hook" do
    test "score ranks ahead of the strategy key" do
      resources = [
        resource("a", fairness(assignments_count: 0)),
        resource("b", fairness(assignments_count: 9))
      ]

      # Round-robin alone picks "a"; the scorer favours "b".
      scorer = fn resource, ctx -> if resource.id == ctx.favourite, do: 100, else: 0 end

      assert {:ok, [%Resource{id: "b"}]} =
               winner(resources,
                 strategy: :round_robin,
                 scorer: scorer,
                 routing_context: %{favourite: "b"}
               )
    end
  end
end
