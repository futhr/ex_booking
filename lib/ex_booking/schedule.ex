defmodule ExBooking.Schedule do
  @moduledoc """
  Wall-time schedule expansion.

  `ExBooking.Schedule` turns weekly windows, date overrides, and blackouts
  into concrete UTC intervals. It resolves ambiguous fall-back wall times to
  their first occurrence and snaps spring-forward gaps to the first valid
  instant after the gap.

  ## Example

      iex> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> {:ok, [interval]} =
      ...>   ExBooking.Schedule.expand(rule, ~U[2026-07-13 00:00:00Z], ~U[2026-07-13 23:59:59Z])
      ...>
      ...> {interval.start_at, interval.end_at}
      {~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z]}

  """

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval

  @utc "Etc/UTC"
  @timezone_validation_instant ~U[2026-01-01 00:00:00Z]

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
  @spec expand(AvailabilityRule.t(), DateTime.t(), DateTime.t()) ::
          {:ok, [Interval.t()]} | {:error, {:invalid, atom(), term()}}
  def expand(%AvailabilityRule{} = rule, %DateTime{} = from, %DateTime{} = until) do
    with :ok <- validate(rule),
         {:ok, bounds} <- bounds(from, until) do
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
  end

  @doc """
  Validates a rule's timezone and wall-time window shapes before expansion.

  Weekly windows require an ISO weekday and `Time` start/end values. Override
  windows require a `Date` plus `Time` start/end values. Invalid caller-built
  rules return stable tagged errors instead of raising during timezone or map
  access.

  ## Example

      iex> rule = %ExBooking.AvailabilityRule{timezone: "Etc/UTC", windows: []}
      ...> ExBooking.Schedule.validate(rule)
      :ok

  """
  @spec validate(AvailabilityRule.t()) :: :ok | {:error, {:invalid, atom(), term()}}
  def validate(%AvailabilityRule{} = rule) do
    with :ok <- validate_timezone(rule.timezone),
         :ok <- validate_weekly_windows(rule.windows),
         :ok <- validate_overrides(rule.overrides),
         :ok <- validate_blackouts(rule.blackouts),
         :ok <- validate_non_negative(rule.lead_time_min, :lead_time_min),
         :ok <- validate_optional_positive(rule.booking_window_days, :booking_window_days),
         :ok <- validate_optional_positive(rule.max_per_day, :max_per_day) do
      validate_buffers(rule.buffers)
    end
  end

  defp validate_blackouts(blackouts) when is_list(blackouts) do
    blackouts
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {blackout, index}, :ok ->
      case Interval.validate(blackout) do
        :ok ->
          {:cont, :ok}

        {:error, {:invalid, :interval, detail}} ->
          {:halt, {:error, {:invalid, :blackouts, {index, detail}}}}
      end
    end)
  end

  defp validate_blackouts(value), do: {:error, {:invalid, :blackouts, value}}

  defp validate_non_negative(value, _) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid, field, value}}

  defp validate_optional_positive(nil, _), do: :ok
  defp validate_optional_positive(value, _) when is_integer(value) and value > 0, do: :ok
  defp validate_optional_positive(value, field), do: {:error, {:invalid, field, value}}

  defp validate_buffers(%{before_min: before_min, after_min: after_min} = buffers)
       when map_size(buffers) == 2 and is_integer(before_min) and before_min >= 0 and
              is_integer(after_min) and after_min >= 0,
       do: :ok

  defp validate_buffers(value), do: {:error, {:invalid, :rule_buffers, value}}

  defp bounds(from, until) do
    case Interval.new(from, until) do
      {:ok, interval} -> {:ok, interval}
      {:error, _} -> {:error, {:invalid, :horizon, :not_increasing}}
    end
  end

  defp validate_timezone(timezone) when is_binary(timezone) do
    case DateTime.shift_zone(@timezone_validation_instant, timezone) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, {:invalid, :rule_timezone, timezone}}
    end
  end

  defp validate_timezone(timezone), do: {:error, {:invalid, :rule_timezone, timezone}}

  defp validate_weekly_windows(windows) when is_list(windows) do
    windows
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {window, index}, :ok ->
      if weekly_window?(window) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid, :windows, {:weekly, index, window}}}}
      end
    end)
  end

  defp validate_weekly_windows(windows),
    do: {:error, {:invalid, :windows, {:weekly, :not_a_list, windows}}}

  defp validate_overrides(overrides) when is_list(overrides) do
    overrides
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {override, index}, :ok ->
      case validate_override(override, index) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_overrides(overrides),
    do: {:error, {:invalid, :overrides, {:not_a_list, overrides}}}

  defp validate_override(%{date: %Date{}, windows: windows}, override_index)
       when is_list(windows) do
    windows
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {window, window_index}, :ok ->
      if override_window?(window) do
        {:cont, :ok}
      else
        detail = {:window, override_index, window_index, window}
        {:halt, {:error, {:invalid, :overrides, detail}}}
      end
    end)
  end

  defp validate_override(override, index),
    do: {:error, {:invalid, :overrides, {:entry, index, override}}}

  defp weekly_window?(%{
         weekday: weekday,
         start_time: %Time{},
         end_time: %Time{}
       }),
       do: is_integer(weekday) and weekday in 1..7

  defp weekly_window?(_), do: false

  defp override_window?(%{start_time: %Time{}, end_time: %Time{}}), do: true
  defp override_window?(_), do: false

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
      {:error, _} -> []
    end
  end

  defp crosses_midnight?(window) do
    Time.compare(window.end_time, window.start_time) in [:lt, :eq]
  end

  defp resolve(date, time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _} -> first
      {:gap, _, just_after} -> just_after
    end
  end

  defp to_utc(datetime), do: DateTime.shift_zone!(datetime, @utc)

  defp local_date(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end
end
