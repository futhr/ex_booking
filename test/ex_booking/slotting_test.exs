defmodule ExBooking.SlottingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  import ExBooking.TestGenerators

  alias ExBooking.Interval
  alias ExBooking.Slotting

  doctest ExBooking.Slotting

  describe "generate_slots/4" do
    test "slot interval is independent of duration" do
      free = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])

      starts =
        free
        |> Slotting.generate_slots(30, 15)
        |> Enum.map(& &1.start_at)

      assert starts == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-13 09:15:00Z],
               ~U[2026-07-13 09:30:00Z]
             ]
    end

    test "duration-coupled grid still works when step equals duration" do
      free = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])

      starts =
        free
        |> Slotting.generate_slots(30, 30)
        |> Enum.map(& &1.start_at)

      assert starts == [~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z]]
    end

    test "a window shorter than the duration yields no slots" do
      free = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:20:00Z])

      assert Slotting.generate_slots(free, 30, 15) == []
    end

    test "slots carry kind: :available" do
      free = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])

      assert Enum.all?(Slotting.generate_slots(free, 30, 15), &(&1.kind == :available))
    end

    test "clock alignment skips the partial leading offset" do
      free = Interval.new!(~U[2026-07-13 09:07:00Z], ~U[2026-07-13 10:00:00Z])

      starts =
        free
        |> Slotting.generate_slots(30, 15, align: :clock)
        |> Enum.map(& &1.start_at)

      assert starts == [~U[2026-07-13 09:15:00Z], ~U[2026-07-13 09:30:00Z]]
    end

    test "clock alignment removes seconds and microseconds" do
      free =
        Interval.new!(
          ~U[2026-07-13 09:07:30.500000Z],
          ~U[2026-07-13 10:00:00.000000Z]
        )

      assert [%Interval{start_at: ~U[2026-07-13 09:15:00Z]} | _] =
               Slotting.generate_slots(free, 30, 15, align: :clock)
    end

    test "free-start alignment remains the default" do
      free = Interval.new!(~U[2026-07-13 09:07:00Z], ~U[2026-07-13 10:00:00Z])

      starts =
        free
        |> Slotting.generate_slots(30, 15)
        |> Enum.map(& &1.start_at)

      assert starts == [~U[2026-07-13 09:07:00Z], ~U[2026-07-13 09:22:00Z]]
    end
  end

  describe "generate_all/4" do
    test "deduplicates identical starts across free intervals and sorts" do
      a = Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 10:30:00Z])
      b = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      c = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])

      starts =
        [a, b, c]
        |> Slotting.generate_all(30, 30)
        |> Enum.map(& &1.start_at)

      assert starts == [~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z]]
    end
  end

  describe "slotting properties" do
    property "every slot fits inside its free interval" do
      check all(free <- interval(), {duration_min, step_min} <- duration_and_step()) do
        for slot <- Slotting.generate_slots(free, duration_min, step_min) do
          assert Interval.contains?(free, slot)
          assert Interval.duration_min(slot) == duration_min
        end
      end
    end

    property "every slot starts on the grid anchored to the free interval start" do
      check all(free <- interval(), {duration_min, step_min} <- duration_and_step()) do
        for slot <- Slotting.generate_slots(free, duration_min, step_min) do
          offset_min = div(DateTime.diff(slot.start_at, free.start_at, :second), 60)
          assert rem(offset_min, step_min) == 0
        end
      end
    end

    property "clock-aligned slots start on UTC clock boundaries" do
      check all(free <- interval(), {duration_min, step_min} <- duration_and_step()) do
        if rem(1_440, step_min) == 0 do
          slots = Slotting.generate_slots(free, duration_min, step_min, align: :clock)

          if first = List.first(slots) do
            minutes_since_midnight = first.start_at.hour * 60 + first.start_at.minute
            assert rem(minutes_since_midnight, step_min) == 0
            assert first.start_at.second == 0
            assert first.start_at.microsecond == {0, 0}
          end
        end
      end
    end

    property "consecutive slot starts differ by exactly the step" do
      check all(free <- interval(), {duration_min, step_min} <- duration_and_step()) do
        free
        |> Slotting.generate_slots(duration_min, step_min)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [earlier, later] ->
          assert DateTime.diff(later.start_at, earlier.start_at, :second) == step_min * 60
        end)
      end
    end

    property "generate_all/4 output is sorted with unique starts" do
      check all(free_intervals <- intervals(6), {duration_min, step_min} <- duration_and_step()) do
        starts =
          free_intervals
          |> Slotting.generate_all(duration_min, step_min)
          |> Enum.map(& &1.start_at)

        expected =
          starts
          |> Enum.uniq()
          |> Enum.sort(DateTime)

        assert starts == expected
      end
    end
  end
end
