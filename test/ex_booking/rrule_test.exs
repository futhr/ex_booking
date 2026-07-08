defmodule ExBooking.RRuleTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.RRule

  doctest ExBooking.RRule

  @dtstart ~U[2026-07-13 09:00:00Z]
  @from ~U[2026-07-13 00:00:00Z]
  @until ~U[2026-07-20 00:00:00Z]

  describe "parse/1" do
    test "parses the supported weekly subset" do
      assert {:ok, rule} = RRule.parse("RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=MO,WE")

      assert rule.freq == :weekly
      assert rule.interval == 2
      assert rule.count == 4
      assert rule.byday == [1, 3]
    end

    test "rejects unsupported rule parts" do
      assert {:error, {:unsupported, :rrule, "BYSETPOS"}} =
               RRule.parse("FREQ=MONTHLY;BYSETPOS=1")
    end

    test "rejects unsupported frequencies" do
      assert {:error, {:unsupported, :rrule, {:freq, "MONTHLY"}}} =
               RRule.parse("FREQ=MONTHLY")
    end

    test "rejects malformed and duplicate rule parts" do
      assert {:error, {:invalid, :rrule, :freq}} = RRule.parse("COUNT=2")
      assert {:error, {:invalid, :rrule, :part}} = RRule.parse("FREQ")

      assert {:error, {:invalid, :rrule, {:duplicate, "COUNT"}}} =
               RRule.parse("FREQ=DAILY;COUNT=1;COUNT=2")
    end

    test "rejects invalid numeric, date, and weekday values" do
      assert {:error, {:invalid, :rrule, :interval}} = RRule.parse("FREQ=DAILY;INTERVAL=0")
      assert {:error, {:invalid, :rrule, :count}} = RRule.parse("FREQ=DAILY;COUNT=never")
      assert {:error, {:invalid, :rrule, :until}} = RRule.parse("FREQ=DAILY;UNTIL=20260713")
      assert {:error, {:unsupported, :rrule, :byday}} = RRule.parse("FREQ=DAILY;BYDAY=MO")
      assert {:error, {:invalid, :rrule, :byday}} = RRule.parse("FREQ=WEEKLY;BYDAY=XX")
    end
  end

  describe "expand/5" do
    test "expands daily recurrences with count" do
      assert {:ok, intervals} =
               RRule.expand("FREQ=DAILY;COUNT=3", @dtstart, 30, @from, @until)

      assert Enum.map(intervals, & &1.start_at) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-14 09:00:00Z],
               ~U[2026-07-15 09:00:00Z]
             ]
    end

    test "expands weekly recurrences with BYDAY" do
      assert {:ok, intervals} =
               RRule.expand(
                 "FREQ=WEEKLY;COUNT=3;BYDAY=MO,WE",
                 @dtstart,
                 30,
                 @from,
                 ~U[2026-07-21 00:00:00Z]
               )

      assert Enum.map(intervals, & &1.start_at) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-15 09:00:00Z],
               ~U[2026-07-20 09:00:00Z]
             ]
    end

    test "honors UNTIL and horizon bounds" do
      assert {:ok, intervals} =
               RRule.expand(
                 "FREQ=DAILY;UNTIL=20260715T090000Z",
                 @dtstart,
                 30,
                 @from,
                 @until
               )

      assert Enum.map(intervals, & &1.start_at) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-14 09:00:00Z],
               ~U[2026-07-15 09:00:00Z]
             ]
    end

    test "expands a parsed rule struct directly" do
      rule = %RRule{freq: :daily, count: 2}

      assert {:ok, intervals} = RRule.expand(rule, @dtstart, 30, @from, @until)

      assert Enum.map(intervals, & &1.start_at) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-14 09:00:00Z]
             ]
    end

    test "weekly rules without BYDAY repeat from DTSTART" do
      assert {:ok, intervals} =
               RRule.expand("FREQ=WEEKLY;COUNT=2", @dtstart, 30, @from, ~U[2026-07-28 00:00:00Z])

      assert Enum.map(intervals, & &1.start_at) == [
               ~U[2026-07-13 09:00:00Z],
               ~U[2026-07-20 09:00:00Z]
             ]
    end
  end

  describe "ExBooking.expand_rrule/4" do
    test "validates horizon options and delegates expansion" do
      assert {:ok, [interval]} =
               ExBooking.expand_rrule("FREQ=DAILY;COUNT=1", @dtstart, 30,
                 from: @from,
                 until: @until
               )

      assert interval.start_at == @dtstart
    end
  end
end
