defmodule ExBooking.IntervalTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  import ExBooking.TestGenerators

  alias ExBooking.Interval

  doctest ExBooking.Interval

  describe "new/3" do
    test "rejects reversed bounds" do
      assert {:error, {:invalid, :interval, :empty_or_reversed}} =
               Interval.new(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 09:00:00Z])
    end

    test "carries kind and meta" do
      {:ok, interval} =
        Interval.new(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z],
          kind: :busy,
          meta: %{source: "google"}
        )

      assert interval.kind == :busy
      assert interval.meta == %{source: "google"}
    end

    test "new!/3 raises on invalid bounds" do
      assert_raise ArgumentError, fn ->
        Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 10:00:00Z])
      end
    end

    test "normalizes zoned endpoints to UTC and rejects non-datetimes" do
      start_at = DateTime.shift_zone!(~U[2026-07-13 09:00:00Z], "Europe/Stockholm")
      end_at = DateTime.shift_zone!(~U[2026-07-13 10:00:00Z], "Europe/Stockholm")

      assert {:ok,
              %Interval{start_at: ~U[2026-07-13 09:00:00Z], end_at: ~U[2026-07-13 10:00:00Z]}} =
               Interval.new(start_at, end_at)

      assert {:error, {:invalid, :interval, :datetime_required}} =
               Interval.new(~N[2026-07-13 09:00:00], end_at)
    end

    test "validate/1 rejects caller-built non-UTC and reversed structs" do
      zoned = DateTime.shift_zone!(~U[2026-07-13 09:00:00Z], "Europe/Stockholm")

      assert {:error, {:invalid, :interval, :not_utc}} =
               Interval.validate(%Interval{start_at: zoned, end_at: ~U[2026-07-13 10:00:00Z]})

      assert {:error, {:invalid, :interval, :empty_or_reversed}} =
               Interval.validate(%Interval{
                 start_at: ~U[2026-07-13 10:00:00Z],
                 end_at: ~U[2026-07-13 09:00:00Z]
               })
    end
  end

  describe "subtract/2" do
    test "no overlap returns the minuend unchanged" do
      a = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      b = Interval.new!(~U[2026-07-13 11:00:00Z], ~U[2026-07-13 12:00:00Z])

      assert Interval.subtract(a, b) == [a]
    end

    test "full containment returns empty" do
      a = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      b = Interval.new!(~U[2026-07-13 08:00:00Z], ~U[2026-07-13 11:00:00Z])

      assert Interval.subtract(a, b) == []
    end

    test "left overlap trims the start" do
      a = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      b = Interval.new!(~U[2026-07-13 08:30:00Z], ~U[2026-07-13 09:30:00Z])

      assert [%Interval{start_at: ~U[2026-07-13 09:30:00Z], end_at: ~U[2026-07-13 10:00:00Z]}] =
               Interval.subtract(a, b)
    end

    test "remainders keep the minuend's kind and meta" do
      a =
        Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 12:00:00Z],
          kind: :available,
          meta: %{rule: "weekday"}
        )

      b = Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])

      assert [left, right] = Interval.subtract(a, b)
      assert left.kind == :available and right.kind == :available
      assert left.meta == %{rule: "weekday"} and right.meta == %{rule: "weekday"}
    end
  end

  describe "merge/1" do
    test "coalesces touching intervals" do
      a = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      b = Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])
      c = Interval.new!(~U[2026-07-13 12:00:00Z], ~U[2026-07-13 13:00:00Z])

      assert [merged, ^c] = Interval.merge([c, b, a])
      assert merged.start_at == ~U[2026-07-13 09:00:00Z]
      assert merged.end_at == ~U[2026-07-13 11:00:00Z]
    end

    test "empty input yields empty output" do
      assert Interval.merge([]) == []
    end
  end

  describe "clip/2" do
    test "disjoint bounds yield nil" do
      a = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      bounds = Interval.new!(~U[2026-07-13 11:00:00Z], ~U[2026-07-13 12:00:00Z])

      assert Interval.clip(a, bounds) == nil
    end
  end

  describe "intersect/2" do
    test "handles touching, nested, disjoint, and equal-end intervals in deterministic order" do
      left = [
        Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 11:00:00Z],
          kind: :available,
          meta: %{source: "left"}
        ),
        Interval.new!(~U[2026-07-13 12:00:00Z], ~U[2026-07-13 13:00:00Z])
      ]

      right = [
        Interval.new!(~U[2026-07-13 08:00:00Z], ~U[2026-07-13 10:00:00Z]),
        Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z]),
        Interval.new!(~U[2026-07-13 13:00:00Z], ~U[2026-07-13 14:00:00Z])
      ]

      assert [common] = Interval.intersect(left, right)
      assert common.start_at == ~U[2026-07-13 09:00:00Z]
      assert common.end_at == ~U[2026-07-13 11:00:00Z]
      assert common.kind == :available
      assert common.meta == %{source: "left"}
    end
  end

  describe "algebra properties" do
    property "generated UTC intervals satisfy the public invariant" do
      check all(value <- interval()) do
        assert :ok = Interval.validate(value)
      end
    end

    property "overlaps?/2 is symmetric" do
      check all(a <- interval(), b <- interval()) do
        assert Interval.overlaps?(a, b) == Interval.overlaps?(b, a)
      end
    end

    property "subtract/2 remainders are contained in the minuend and disjoint from the subtrahend" do
      check all(a <- interval(), b <- interval()) do
        remainders = Interval.subtract(a, b)

        for remainder <- remainders do
          assert Interval.contains?(a, remainder)
          refute Interval.overlaps?(remainder, b)
        end

        case remainders do
          [left, right] -> refute Interval.overlaps?(left, right)
          _ -> :ok
        end
      end
    end

    property "merge/1 is idempotent and produces sorted, disjoint, non-adjacent normal form" do
      check all(input <- intervals()) do
        merged = Interval.merge(input)

        assert Interval.merge(merged) == merged

        merged
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [earlier, later] ->
          assert DateTime.compare(earlier.end_at, later.start_at) == :lt
        end)
      end
    end

    property "merge/1 preserves membership: every input instant stays covered" do
      check all(input <- intervals()) do
        merged = Interval.merge(input)

        for original <- input do
          assert Enum.any?(merged, &Interval.contains?(&1, original))
        end
      end
    end

    property "subtract_all/2 output never overlaps any subtrahend" do
      check all(minuends <- intervals(), subtrahends <- intervals()) do
        result = Interval.subtract_all(minuends, subtrahends)

        for interval <- result, busy <- subtrahends do
          refute Interval.overlaps?(interval, busy)
        end

        starts = Enum.map(result, & &1.start_at)
        assert starts == Enum.sort(starts, DateTime)
      end
    end

    property "clip/2 result is contained in both operands" do
      check all(a <- interval(), bounds <- interval()) do
        case Interval.clip(a, bounds) do
          nil ->
            :ok

          clipped ->
            assert Interval.contains?(a, clipped)
            assert Interval.contains?(bounds, clipped)
        end
      end
    end

    property "linear intersection equals the Cartesian reference on normalized sets" do
      check all(left <- intervals(), right <- intervals()) do
        reference =
          for a <- Interval.merge(left),
              b <- Interval.merge(right),
              clipped = Interval.clip(a, b),
              clipped != nil,
              do: clipped

        assert Interval.intersect(left, right) == Interval.merge(reference)
      end
    end

    property "inflate/3 then clip/2 by the same bounds never exceeds bounds" do
      check all(
              a <- interval(),
              before_min <- StreamData.integer(0..60),
              after_min <- StreamData.integer(0..60)
            ) do
        inflated = Interval.inflate(a, before_min, after_min)

        case Interval.clip(inflated, a) do
          nil -> :ok
          clipped -> assert Interval.contains?(a, clipped)
        end

        assert Interval.duration_min(inflated) ==
                 Interval.duration_min(a) + before_min + after_min
      end
    end
  end
end
