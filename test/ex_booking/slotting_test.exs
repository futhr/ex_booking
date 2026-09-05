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
          offset = DateTime.diff(slot.start_at, free.start_at, :microsecond)
          assert rem(offset, step_min * 60_000_000) == 0
        end
      end
    end

    property "every clock-aligned slot lies on the UTC grid, including across midnight" do
      check all(
              fraction <- integer(1..59_999_999),
              step_min <- member_of([5, 10, 15, 20, 30, 60, 120]),
              duration_min <- integer(1..120)
            ) do
        start_at = DateTime.add(~U[2026-07-13 23:57:00Z], fraction, :microsecond)
        free = Interval.new!(start_at, DateTime.add(start_at, 2, :day))
        slots = Slotting.generate_slots(free, duration_min, step_min, align: :clock)
        assert length(slots) >= 2

        for slot <- slots do
          minutes_since_midnight = slot.start_at.hour * 60 + slot.start_at.minute
          assert rem(minutes_since_midnight, step_min) == 0
          assert slot.start_at.second == 0
          assert slot.start_at.microsecond == {0, 0}
          assert Interval.contains?(free, slot)
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

  property "equal instants deduplicate regardless of display precision" do
    check all(precision <- integer(0..6)) do
      free = Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      alternate = %{free | start_at: %{free.start_at | microsecond: {0, precision}}}

      assert Slotting.generate_all([free, alternate], 30, 15) ==
               Slotting.generate_slots(free, 30, 15)
    end
  end

  test "deduplication preserves distinct fall-back instants in both DST zones" do
    fixtures = [
      {"Europe/Stockholm", ~D[2026-10-25], ~T[02:30:00]},
      {"America/New_York", ~D[2026-11-01], ~T[01:30:00]}
    ]

    for {zone, date, time} <- fixtures do
      {:ambiguous, first, second} = DateTime.new(date, time, zone)

      intervals =
        Enum.map([first, second], fn start ->
          Interval.new!(start, DateTime.add(start, 30, :minute))
        end)

      assert length(Slotting.generate_all(intervals ++ intervals, 30, 30)) == 2
    end
  end
end
