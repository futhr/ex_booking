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

    test "normalizes duration periods with a busy FBTYPE" do
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

    test "validates but discards FBTYPE=FREE periods case-insensitively" do
      assert {:ok, []} =
               ICalendar.free_busy("freebusy;fbtype=free:20260713T090000Z/20260713T093000Z")

      assert {:error, {:invalid, :freebusy, :period}} =
               ICalendar.free_busy("FREEBUSY;FBTYPE=FREE:not-a-period")
    end

    test "defaults absent and unknown FBTYPE values to busy" do
      ics = """
      FREEBUSY:20260713T090000Z/20260713T093000Z
      FREEBUSY;FBTYPE=X-CUSTOM:20260713T100000Z/20260713T103000Z
      """

      assert {:ok, [first, second]} = ICalendar.free_busy(ics)
      assert first.start_at == ~U[2026-07-13 09:00:00Z]
      assert second.start_at == ~U[2026-07-13 10:00:00Z]
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

    test "rejects a FREEBUSY property without a value separator" do
      assert {:error, {:invalid, :freebusy, :property}} =
               ICalendar.free_busy("FREEBUSY;FBTYPE=BUSY")
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

    test "supports RFC 5545 week and ordered date-time durations" do
      assert {:ok, [week]} = ICalendar.free_busy("FREEBUSY:20260713T090000Z/P1W")
      assert week.end_at == ~U[2026-07-20 09:00:00Z]

      assert {:ok, [mixed]} = ICalendar.free_busy("FREEBUSY:20260713T090000Z/P1DT2H3M4S")
      assert mixed.end_at == ~U[2026-07-14 11:03:04Z]
    end

    test "rejects invalid duration mixtures and a trailing time designator" do
      for duration <- ["PT1H1S", "P1DT", "P1W1D", "P0D", "PT0S"] do
        assert {:error, {:invalid, :freebusy, :duration}} =
                 ICalendar.free_busy("FREEBUSY:20260713T090000Z/#{duration}")
      end
    end
  end

  describe "ExBooking.import_ics_free_busy/1" do
    test "delegates normalization" do
      assert {:ok, [busy]} =
               ExBooking.import_ics_free_busy("FREEBUSY:20260713T090000Z/PT30M")

      assert busy.end_at == ~U[2026-07-13 09:30:00Z]
    end
  end

  @tag audit_finding: "A15"
  test "empty FREEBUSY periods are malformed even when marked FREE" do
    for values <- ["", ",,", ",20260713T090000Z/PT30M", "20260713T090000Z/PT30M,"],
        property <- ["FREEBUSY", "FREEBUSY;FBTYPE=FREE"] do
      assert {:error, {:invalid, :freebusy, :period}} =
               ExBooking.ICalendar.free_busy(property <> ":" <> values)
    end
  end

  test "rejects repeated FBTYPE instead of discarding ambiguous busy time" do
    for parameters <- [
          "FBTYPE=FREE;FBTYPE=BUSY",
          "FBTYPE=BUSY;fbtype=FREE",
          "FBTYPE=FREE;FBTYPE=FREE"
        ] do
      assert {:error, {:invalid, :freebusy, :property}} =
               ExBooking.import_ics_free_busy("FREEBUSY;#{parameters}:20260713T090000Z/PT30M")
    end
  end

  test "quoted extension values cannot split headers or introduce FBTYPE" do
    for parameters <- [
          ~s(X-URL="https://example.test/a;b,c"),
          ~s(X-NOTE="ignored;FBTYPE=FREE:still ignored"),
          ~s(X-NOTE="ignored";FBTYPE=BUSY;X-NOTE="again")
        ] do
      assert {:ok, [busy]} =
               ICalendar.free_busy("FREEBUSY;#{parameters}:20260713T090000Z/PT30M")

      assert busy.start_at == ~U[2026-07-13 09:00:00Z]
      assert busy.end_at == ~U[2026-07-13 09:30:00Z]
    end
  end

  test "rejects malformed headers and invalid text encoding" do
    for parameters <- [~s(X-NOTE="unclosed), "FBTYPE", "FBTYPE=", ";FBTYPE=BUSY"] do
      assert {:error, {:invalid, :freebusy, :property}} =
               ICalendar.free_busy("FREEBUSY;#{parameters}:20260713T090000Z/PT30M")
    end

    assert {:error, {:invalid, :freebusy, :encoding}} = ICalendar.free_busy(<<255>>)
  end

  test "duration endpoints remain representable and the final second is allowed" do
    for period <- ["20260713T090000Z/PT99999999999999999999S", "99991231T235959Z/PT1S"] do
      assert {:error, {:invalid, :freebusy, :duration}} =
               ICalendar.free_busy("FREEBUSY:" <> period)
    end

    assert {:ok, [busy]} = ICalendar.free_busy("FREEBUSY:99991231T235958Z/PT1S")
    assert busy.end_at == ~U[9999-12-31 23:59:59Z]
  end
end
