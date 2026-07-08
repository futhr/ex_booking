defmodule ExBooking.Slotting do
  @moduledoc """
  Slot-grid generation over free intervals.

  The grid step is independent of the meeting duration by design: a 30-minute
  meeting can sit on a 15-minute grid. By default the grid is anchored to each
  free interval's start; `align: :clock` anchors starts to UTC clock boundaries.
  See `docs/specs/SP.03-algorithms.md` §4.
  """

  alias ExBooking.Interval

  @doc """
  Generates candidate slots of `duration_min` minutes on a `step_min` grid
  anchored to the free interval's start by default.

  Options:

    * `:align` — `:free_start` (default) or `:clock`

  Every returned slot fits entirely inside `free` and carries
  `kind: :available`. Returns slots sorted ascending by start.

  ## Examples

      iex> free = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...> slots = ExBooking.Slotting.generate_slots(free, 30, 15)
      ...> Enum.map(slots, & &1.start_at)
      [~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:15:00Z], ~U[2026-07-13 09:30:00Z]]

      iex> free = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:20:00Z])
      ...> ExBooking.Slotting.generate_slots(free, 30, 15)
      []

  """
  @spec generate_slots(Interval.t(), pos_integer(), pos_integer(), keyword()) :: [Interval.t()]
  def generate_slots(%Interval{} = free, duration_min, step_min, opts \\ [])
      when is_integer(duration_min) and duration_min > 0 and
             is_integer(step_min) and step_min > 0 do
    free
    |> first_start(step_min, Keyword.get(opts, :align, :free_start))
    |> Stream.iterate(&DateTime.add(&1, step_min, :minute))
    |> Stream.map(fn start_at ->
      {start_at, DateTime.add(start_at, duration_min, :minute)}
    end)
    |> Stream.take_while(fn {_start_at, end_at} ->
      DateTime.compare(end_at, free.end_at) != :gt
    end)
    |> Enum.map(fn {start_at, end_at} ->
      %Interval{start_at: start_at, end_at: end_at, kind: :available}
    end)
  end

  @doc """
  Generates slots across many free intervals, deduplicated and sorted.

  Duplicate starts can occur when free intervals from different sources
  overlap after DST normalization; the first occurrence wins.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...> b = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...> ExBooking.Slotting.generate_all([a, b], 30, 30) |> length()
      1

  """
  @spec generate_all([Interval.t()], pos_integer(), pos_integer(), keyword()) :: [Interval.t()]
  def generate_all(free_intervals, duration_min, step_min, opts \\ []) do
    free_intervals
    |> Enum.flat_map(&generate_slots(&1, duration_min, step_min, opts))
    |> Enum.uniq_by(& &1.start_at)
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  defp first_start(free, _step_min, :free_start), do: free.start_at

  defp first_start(free, step_min, :clock) do
    case rem(minutes_since_midnight(free.start_at), step_min) do
      0 -> free.start_at
      offset -> DateTime.add(free.start_at, step_min - offset, :minute)
    end
  end

  defp minutes_since_midnight(datetime), do: datetime.hour * 60 + datetime.minute
end
