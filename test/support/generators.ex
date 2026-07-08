defmodule ExBooking.TestGenerators do
  @moduledoc """
  StreamData generators for property tests over the interval algebra and
  slot generation (spec 06 §3). All generated datetimes are minute-aligned
  within a bounded horizon so failures shrink to readable cases.
  """

  import StreamData

  alias ExBooking.Interval

  @base ~U[2026-07-13 00:00:00Z]

  @doc "Generates a minute-aligned interval up to ten hours long."
  @spec interval() :: StreamData.t(Interval.t())
  def interval do
    bind(integer(0..20_000), fn start_min ->
      map(integer(1..600), fn length_min ->
        Interval.new!(minute(start_min), minute(start_min + length_min))
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
