defmodule ExBooking.Schedule do
  @moduledoc """
  Wall-time expansion of availability windows into concrete UTC intervals,
  applying the DST rules from `docs/specs/SP.03-algorithms.md` §2: ambiguous
  wall times resolve to the first occurrence, gapped wall times snap forward.

  Windows are weekly wall-time ranges in the rule's timezone; overrides replace
  a day's windows (an empty override removes the day); blackouts subtract
  absolute intervals. The result is merged, UTC-normalized offerable time.
  """

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval

  @utc "Etc/UTC"

  @doc """
  Expands a rule's weekly windows, overrides, and blackouts over
  `[from, until]` into merged, UTC-normalized offerable intervals.

  ## Examples

      iex> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}]
      ...> }
      ...>
      ...> {:ok, [interval]} =
      ...>   ExBooking.Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])
      ...>
      ...> {interval.start_at, interval.end_at}
      {~U[2026-07-13 09:00:00Z], ~U[2026-07-13 17:00:00Z]}

  """
  @spec expand(AvailabilityRule.t(), DateTime.t(), DateTime.t()) :: {:ok, [Interval.t()]}
  def expand(%AvailabilityRule{} = rule, %DateTime{} = from, %DateTime{} = until) do
    bounds = Interval.new!(from, until)

    intervals =
      rule
      |> candidate_dates(from, until)
      |> Enum.flat_map(&expand_date(rule, &1))
      |> Interval.subtract_all(rule.blackouts)
      |> Enum.map(&Interval.clip(&1, bounds))
      |> Enum.reject(&is_nil/1)
      |> Interval.merge()

    {:ok, intervals}
  end

  # Rule-timezone dates whose windows could overlap [from, until]. The extra day
  # at the front catches cross-midnight windows that start the previous evening.
  defp candidate_dates(rule, from, until) do
    tz = rule.timezone
    first = Date.add(local_date(from, tz), -1)
    last = local_date(until, tz)

    Enum.to_list(Date.range(first, last))
  end

  defp expand_date(rule, date) do
    date
    |> windows_for(rule)
    |> Enum.flat_map(&expand_window(&1, date, rule.timezone))
  end

  # An override for the date replaces the weekly windows entirely; an override
  # with empty windows removes the day.
  defp windows_for(date, rule) do
    case Enum.find(rule.overrides, &(&1.date == date)) do
      nil -> Enum.filter(rule.windows, &(&1.weekday == Date.day_of_week(date)))
      %{windows: windows} -> windows
    end
  end

  defp expand_window(window, date, tz) do
    start_at = resolve(date, window.start_time, tz)
    end_date = if crosses_midnight?(window), do: Date.add(date, 1), else: date
    end_at = resolve(end_date, window.end_time, tz)

    case Interval.new(to_utc(start_at), to_utc(end_at)) do
      {:ok, interval} -> [interval]
      # A spring-forward gap can snap `start` to or past `end`, emptying the window.
      {:error, _reason} -> []
    end
  end

  defp crosses_midnight?(window) do
    Time.compare(window.end_time, window.start_time) in [:lt, :eq]
  end

  # Resolve a wall time to a concrete instant per the DST rules (SP.03 §2).
  defp resolve(date, time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
      {:gap, _just_before, just_after} -> just_after
    end
  end

  defp to_utc(datetime), do: DateTime.shift_zone!(datetime, @utc)

  defp local_date(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end
end
