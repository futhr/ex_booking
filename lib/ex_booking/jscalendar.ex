defmodule ExBooking.JSCalendar do
  @moduledoc """
  JSCalendar busy-time normalization.

  Callers pass decoded JSCalendar-shaped maps. This module maps supported
  `Event` and `Group` objects into merged UTC busy intervals and rejects
  floating times or recurrence data that require a full adapter.

  ## Example

      iex> event = %{
      ...>   "@type" => "Event",
      ...>   "start" => "2026-07-13T09:00:00",
      ...>   "timeZone" => "Etc/UTC",
      ...>   "duration" => "PT30M"
      ...> }
      ...>
      ...> {:ok, [busy]} = ExBooking.JSCalendar.busy_intervals(event)
      ...> busy.end_at
      ~U[2026-07-13 09:30:00Z]

  """

  alias ExBooking.Interval

  @typedoc "A decoded JSCalendar object."
  @type object :: map()

  @doc """
  Extracts busy intervals from a decoded JSCalendar `Event` or `Group`.

  Supported events require `@type: "Event"`, `start`, `timeZone`, and optional
  `duration` (default `PT0S`). `freeBusyStatus: "free"` and
  `status: "cancelled"` events are ignored. `Group.entries` is a list of
  objects.
  """
  @spec busy_intervals(object()) :: {:ok, [Interval.t()]} | {:error, term()}
  def busy_intervals(%{"@type" => "Event"} = event), do: event_interval(event)

  def busy_intervals(%{"@type" => "Group", "entries" => entries}) do
    entries
    |> normalize_entries()
    |> parse_entries()
  end

  def busy_intervals(%{"@type" => type}), do: {:error, {:unsupported, :jscalendar, type}}
  def busy_intervals(_), do: {:error, {:invalid, :jscalendar, :object}}

  defp normalize_entries(entries) when is_list(entries), do: entries
  defp normalize_entries(_), do: :invalid

  defp parse_entries(:invalid), do: {:error, {:invalid, :jscalendar, :entries}}

  defp parse_entries(entries) do
    result =
      Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
        case busy_intervals(entry) do
          {:ok, intervals} -> {:cont, {:ok, intervals ++ acc}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, intervals} -> {:ok, Interval.merge(intervals)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp event_interval(%{"status" => "cancelled"}), do: {:ok, []}
  defp event_interval(%{"freeBusyStatus" => "free"}), do: {:ok, []}

  defp event_interval(%{"freeBusyStatus" => status}) when status not in ["busy", nil] do
    {:error, {:unsupported, :jscalendar, {:free_busy_status, status}}}
  end

  defp event_interval(%{"recurrenceRules" => _}) do
    {:error, {:unsupported, :jscalendar, :recurrence}}
  end

  defp event_interval(%{"start" => start_value, "timeZone" => timezone} = event)
       when is_binary(start_value) and is_binary(timezone) do
    with {:ok, start_at} <- parse_local_datetime(start_value, timezone),
         {:ok, duration} <- parse_duration(Map.get(event, "duration", "PT0S")),
         {:ok, end_at} <- add_duration(start_at, duration, timezone) do
      build_interval(start_at, end_at)
    end
  end

  defp event_interval(%{"start" => _}),
    do: {:error, {:unsupported, :jscalendar, :floating_time}}

  defp event_interval(_), do: {:error, {:invalid, :jscalendar, :event}}

  defp parse_local_datetime(value, timezone) when is_binary(value) do
    if valid_local_datetime_format?(value) do
      case NaiveDateTime.from_iso8601(value) do
        {:ok, naive} ->
          resolve_datetime(NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive), timezone)

        {:error, _} ->
          {:error, {:invalid, :jscalendar, :start}}
      end
    else
      {:error, {:invalid, :jscalendar, :start}}
    end
  end

  defp resolve_datetime(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _} -> {:ok, first}
      {:gap, before_gap, _} -> {:ok, apply_offset_before_gap(date, time, before_gap)}
      {:error, _} -> {:error, {:invalid, :jscalendar, :timezone}}
    end
  end

  defp valid_local_datetime_format?(value) do
    Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$/, value) and
      canonical_fraction?(fraction(value))
  end

  defp fraction(value) do
    case String.split(value, ".", parts: 2) do
      [_] -> ""
      [_, fraction] -> fraction
    end
  end

  defp canonical_fraction?(""), do: true
  defp canonical_fraction?(fraction), do: not String.ends_with?(fraction, "0")

  defp apply_offset_before_gap(date, time, before_gap) do
    %DateTime{
      year: date.year,
      month: date.month,
      day: date.day,
      hour: time.hour,
      minute: time.minute,
      second: time.second,
      microsecond: time.microsecond,
      time_zone: before_gap.time_zone,
      zone_abbr: before_gap.zone_abbr,
      utc_offset: before_gap.utc_offset,
      std_offset: before_gap.std_offset,
      calendar: Calendar.ISO
    }
  end

  defp parse_duration(value) when is_binary(value) do
    pattern =
      ~r/^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)(?:\.(\d{1,6}))?S)?)?$/

    case Regex.run(pattern, value) do
      nil ->
        {:error, {:invalid, :jscalendar, :duration}}

      captures ->
        captures
        |> tl()
        |> pad_captures()
        |> duration_parts(value)
    end
  end

  defp parse_duration(_), do: {:error, {:invalid, :jscalendar, :duration}}

  defp pad_captures(captures), do: captures ++ List.duplicate("", 6 - length(captures))

  defp duration_parts([weeks, days, hours, minutes, seconds, fraction], source) do
    duration = %{
      days: parse_duration_part(weeks) * 7 + parse_duration_part(days),
      microseconds:
        (parse_duration_part(hours) * 3_600 + parse_duration_part(minutes) * 60 +
           parse_duration_part(seconds)) * 1_000_000 + fractional_microseconds(fraction)
    }

    components = [weeks, days, hours, minutes, seconds]

    if valid_duration_components?(components, fraction, source) do
      {:ok, duration}
    else
      {:error, {:invalid, :jscalendar, :duration}}
    end
  end

  defp valid_duration_components?([_, _, hours, minutes, seconds] = components, fraction, source) do
    Enum.any?(components, &(&1 != "")) and
      not String.ends_with?(source, "T") and
      not (hours != "" and minutes == "" and seconds != "") and
      canonical_fraction?(fraction)
  end

  defp parse_duration_part(""), do: 0
  defp parse_duration_part(value), do: String.to_integer(value)

  defp fractional_microseconds(""), do: 0

  defp fractional_microseconds(value) do
    value
    |> String.pad_trailing(6, "0")
    |> String.to_integer()
  end

  defp add_duration(start_at, %{days: 0, microseconds: microseconds}, _) do
    {:ok, add_elapsed(start_at, microseconds)}
  end

  defp add_duration(start_at, %{days: days, microseconds: microseconds}, timezone) do
    start_date = DateTime.to_date(start_at)
    shifted_date = Date.add(start_date, days)
    local_time = DateTime.to_time(start_at)

    with {:ok, day_shifted} <- resolve_datetime(shifted_date, local_time, timezone) do
      {:ok, add_elapsed(day_shifted, microseconds)}
    end
  end

  defp add_elapsed(datetime, microseconds) when rem(microseconds, 1_000_000) == 0,
    do: DateTime.add(datetime, div(microseconds, 1_000_000), :second)

  defp add_elapsed(datetime, microseconds), do: DateTime.add(datetime, microseconds, :microsecond)

  defp build_interval(start_at, end_at) do
    if DateTime.compare(start_at, end_at) == :lt do
      with {:ok, interval} <-
             Interval.new(
               DateTime.shift_zone!(start_at, "Etc/UTC"),
               DateTime.shift_zone!(end_at, "Etc/UTC"),
               kind: :busy
             ) do
        {:ok, [interval]}
      end
    else
      {:ok, []}
    end
  end
end
