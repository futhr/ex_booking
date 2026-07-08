defmodule ExBooking.DSTFixturesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.DSTFixtures

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
    end
  end
end
