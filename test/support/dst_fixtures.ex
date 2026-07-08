defmodule ExBooking.DSTFixtures do
  @moduledoc """
  The DST transition corpus required by spec 06 §4.

  Any timezone-sensitive kernel function must be exercised against these
  spring-forward (gap) and fall-back (ambiguity) points for at least
  Europe/Stockholm and America/New_York. The corpus itself is verified by
  `test/ex_booking/dst_fixtures_test.exs` so the dates can be trusted when
  `ExBooking.Schedule` lands (roadmap v0.1).
  """

  @transitions %{
    stockholm: %{
      timezone: "Europe/Stockholm",
      spring_forward: %{
        # 2026-03-29 02:00 CET jumps to 03:00 CEST; 02:xx wall times don't exist
        date: ~D[2026-03-29],
        gap_starts: ~T[02:00:00],
        gap_ends: ~T[03:00:00]
      },
      fall_back: %{
        # 2026-10-25 03:00 CEST falls back to 02:00 CET; 02:xx wall times occur twice
        date: ~D[2026-10-25],
        ambiguous_starts: ~T[02:00:00],
        ambiguous_ends: ~T[03:00:00]
      }
    },
    new_york: %{
      timezone: "America/New_York",
      spring_forward: %{
        # 2026-03-08 02:00 EST jumps to 03:00 EDT
        date: ~D[2026-03-08],
        gap_starts: ~T[02:00:00],
        gap_ends: ~T[03:00:00]
      },
      fall_back: %{
        # 2026-11-01 02:00 EDT falls back to 01:00 EST; 01:xx wall times occur twice
        date: ~D[2026-11-01],
        ambiguous_starts: ~T[01:00:00],
        ambiguous_ends: ~T[02:00:00]
      }
    }
  }

  @doc "All fixture keys."
  @spec zones() :: [atom()]
  def zones, do: Map.keys(@transitions)

  @doc "The full transition fixture for a zone key."
  @spec transitions(atom()) :: map()
  def transitions(zone), do: Map.fetch!(@transitions, zone)

  @doc "A wall time inside the zone's spring-forward gap (does not exist)."
  @spec gap_wall_time(atom()) :: {Date.t(), Time.t(), String.t()}
  def gap_wall_time(zone) do
    %{timezone: tz, spring_forward: sf} = transitions(zone)
    {sf.date, Time.add(sf.gap_starts, 30 * 60), tz}
  end

  @doc "A wall time inside the zone's fall-back overlap (exists twice)."
  @spec ambiguous_wall_time(atom()) :: {Date.t(), Time.t(), String.t()}
  def ambiguous_wall_time(zone) do
    %{timezone: tz, fall_back: fb} = transitions(zone)
    {fb.date, Time.add(fb.ambiguous_starts, 30 * 60), tz}
  end
end
