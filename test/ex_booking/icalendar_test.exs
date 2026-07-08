defmodule ExBooking.ICalendarTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.ICalendar

  doctest ExBooking.ICalendar

  describe "free_busy/1" do
    test "normalizes start-end FREEBUSY periods" do
      ics = """
      BEGIN:VCALENDAR
      BEGIN:VFREEBUSY
      FREEBUSY:20260713T090000Z/20260713T093000Z
      END:VFREEBUSY
      END:VCALENDAR
      """

      assert {:ok, [busy]} = ICalendar.free_busy(ics)
      assert busy.start_at == ~U[2026-07-13 09:00:00Z]
      assert busy.end_at == ~U[2026-07-13 09:30:00Z]
      assert busy.kind == :busy
    end

    test "normalizes duration periods and ignores FBTYPE parameters" do
      ics = """
      BEGIN:VCALENDAR
      BEGIN:VFREEBUSY
      FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260713T090000Z/PT45M
      END:VFREEBUSY
      END:VCALENDAR
      """

      assert {:ok, [busy]} = ICalendar.free_busy(ics)
      assert busy.start_at == ~U[2026-07-13 09:00:00Z]
      assert busy.end_at == ~U[2026-07-13 09:45:00Z]
    end

    test "unfolds folded lines and merges overlapping periods" do
      ics = """
      BEGIN:VCALENDAR
      BEGIN:VFREEBUSY
      FREEBUSY:20260713T090000Z/20260713T093000Z,
       20260713T091500Z/20260713T100000Z
      END:VFREEBUSY
      END:VCALENDAR
      """

      assert {:ok, [busy]} = ICalendar.free_busy(ics)
      assert busy.start_at == ~U[2026-07-13 09:00:00Z]
      assert busy.end_at == ~U[2026-07-13 10:00:00Z]
    end

    test "rejects local date-times" do
      assert {:error, {:unsupported, :freebusy, :datetime}} =
               ICalendar.free_busy("FREEBUSY:20260713T090000/20260713T093000Z")
    end

    test "rejects invalid periods" do
      assert {:error, {:invalid, :freebusy, :period}} =
               ICalendar.free_busy("FREEBUSY:20260713T090000Z")
    end

    test "rejects invalid UTC dates and times" do
      assert {:error, {:invalid, :freebusy, :date}} =
               ICalendar.free_busy("FREEBUSY:20261313T090000Z/20260713T093000Z")

      assert {:error, {:invalid, :freebusy, :time}} =
               ICalendar.free_busy("FREEBUSY:20260713T250000Z/20260713T253000Z")
    end

    test "rejects empty durations" do
      assert {:error, {:invalid, :freebusy, :duration}} =
               ICalendar.free_busy("FREEBUSY:20260713T090000Z/P")
    end

    test "ignores non-FREEBUSY lines" do
      assert {:ok, []} =
               ICalendar.free_busy("""
               BEGIN:VCALENDAR
               DTSTART:20260713T090000Z
               END:VCALENDAR
               """)
    end

    test "supports day durations" do
      assert {:ok, [busy]} = ICalendar.free_busy("FREEBUSY:20260713T090000Z/P1D")

      assert busy.end_at == ~U[2026-07-14 09:00:00Z]
    end
  end

  describe "ExBooking.import_ics_free_busy/1" do
    test "delegates normalization" do
      assert {:ok, [busy]} =
               ExBooking.import_ics_free_busy("FREEBUSY:20260713T090000Z/PT30M")

      assert busy.end_at == ~U[2026-07-13 09:30:00Z]
    end
  end
end
