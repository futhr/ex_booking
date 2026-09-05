defmodule ExBooking.TestGenerators do
  @moduledoc false

  import StreamData

  alias ExBooking.Interval

  @base ~U[2026-07-13 00:00:00Z]

  @doc "Generates an interval up to ten hours long with arbitrary sub-minute precision."
  @spec interval() :: StreamData.t(Interval.t())
  def interval do
    bind(tuple({integer(0..20_000), integer(0..59_999_999)}), fn {start_min, fraction} ->
      map(integer(1..600), fn length_min ->
        start_at = DateTime.add(minute(start_min), fraction, :microsecond)
        Interval.new!(start_at, DateTime.add(start_at, length_min, :minute))
      end)
    end)
  end

  @doc "Generates a list of intervals."
  @spec intervals(non_neg_integer()) :: StreamData.t([Interval.t()])
  def intervals(max_length \\ 12) do
    list_of(interval(), max_length: max_length)
  end

  @doc "Generates `{duration_min, step_min}` including step < duration, step == duration, and step > duration."
  @spec duration_and_step() :: StreamData.t({pos_integer(), pos_integer()})
  def duration_and_step do
    bind(integer(5..120), fn duration_min ->
      map(integer(5..120), fn step_min ->
        {duration_min, step_min}
      end)
    end)
  end

  defp minute(offset), do: DateTime.add(@base, offset, :minute)
end
