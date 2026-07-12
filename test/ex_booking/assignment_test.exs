defmodule ExBooking.AssignmentTest do
  @moduledoc false

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

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :weighted)
    end

    test "rejects zero, negative, and non-numeric weights before division" do
      for weight <- [0, -1, "heavy"] do
        assert {:error, {:invalid, :resource_weight, {"a", ^weight}}} =
                 winner([resource("a", fairness(weight: weight))], strategy: :weighted)
      end
    end

    test "validates every supplied resource before eligibility or sorting" do
      resources = [
        resource("valid", fairness(weight: 1)),
        resource("malformed", fairness(weight: 0))
      ]

      assert {:error, {:invalid, :resource_weight, {"malformed", 0}}} =
               winner(resources, strategy: :weighted)
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

    test "unsupported atoms and tuple shapes return tagged errors" do
      assert {:error, {:invalid, :strategy, :random}} =
               winner([resource("a")], strategy: :random)

      assert {:error, {:invalid, :strategy, {:round_robin, []}}} =
               winner([resource("a")], strategy: {:round_robin, []})

      assert {:error, {:invalid, :strategy, {:owner_first, []}}} =
               winner([resource("a")], strategy: {:owner_first, []})
    end

    test "round-robin ties break by earliest last_assigned_at" do
      resources = [
        resource("a", fairness(assignments_count: 2, last_assigned_at: ~U[2026-07-05 09:00:00Z])),
        resource("b", fairness(assignments_count: 2, last_assigned_at: ~U[2026-07-01 09:00:00Z]))
      ]

      assert {:ok, [%Resource{id: "b"}]} = winner(resources, strategy: :round_robin)
    end

    test "rejects malformed resource containers, ids, fairness, scorer, and opts" do
      assert {:error, {:invalid, :opts, :not_a_keyword_list}} = Assignment.validate([], :bad)
      assert {:error, {:invalid, :resources, :bad}} = Assignment.validate(:bad, [])

      assert {:error, {:invalid, :resource_id, ""}} =
               winner([resource("")], strategy: :first_available)

      assert {:error, {:invalid, :resources, {0, :bad}}} =
               winner([:bad], strategy: :first_available)

      assert {:error, {:invalid, :resource_fairness, {"a", :bad}}} =
               winner([resource("a", :bad)], strategy: :first_available)

      assert {:error, {:invalid, :resource_fairness, {"a", {:unexpected, true}}}} =
               winner([resource("a", %{unexpected: true})], strategy: :first_available)

      assert {:error, {:invalid, :scorer, :bad}} =
               Assignment.validate([resource("a")], scorer: :bad)
    end
  end

  describe "scoring hook" do
    test "score ranks ahead of the strategy key" do
      resources = [
        resource("a", fairness(assignments_count: 0)),
        resource("b", fairness(assignments_count: 9))
      ]

      scorer = fn resource, ctx -> if resource.id == ctx.favourite, do: 100, else: 0 end

      assert {:ok, [%Resource{id: "b"}]} =
               winner(resources,
                 strategy: :round_robin,
                 scorer: scorer,
                 routing_context: %{favourite: "b"}
               )
    end

    test "returns tagged errors for non-numeric and raised scorer results" do
      assert {:error, {:invalid, :scorer_result, {"a", :high}}} =
               winner([resource("a")], scorer: fn _, _ -> :high end)

      assert {:error, {:invalid, :scorer_result, {"a", :raised}}} =
               winner([resource("a")], scorer: fn _, _ -> raise "boom" end)
    end

    test "rejects malformed fairness before strategy sorting" do
      assert {:error, {:invalid, :resource_fairness, {"a", {:priority, "high"}}}} =
               winner([resource("a", %{priority: "high"})], strategy: :priority)

      assert {:error, {:invalid, :resource_fairness, {"a", {:assignments_count, -1}}}} =
               winner([resource("a", %{assignments_count: -1})], strategy: :round_robin)
    end
  end
end
