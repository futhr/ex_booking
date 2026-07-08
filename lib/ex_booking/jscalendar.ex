defmodule ExBooking.JSCalendar do
  @moduledoc """
  Dependency-free JSCalendar busy-time normalization helpers.

  The supported surface is intentionally narrow and pure: callers pass already
  decoded JSCalendar maps, and event objects are normalized into UTC
  `ExBooking.Interval` structs with `kind: :busy`. JSON decoding, persistence,
  recurrence expansion, and vendor-specific extensions remain consumer concerns.
  """

  alias ExBooking.Interval

  @typedoc "A decoded JSCalendar object."
  @type object :: map()

  @doc """
  Extracts busy intervals from a decoded JSCalendar `Event` or `Group`.

  Supported events require `@type: "Event"`, `start`, `timeZone`, and optional
  `duration` (default `PT0S`). `freeBusyStatus: "free"` and
  `status: "cancelled"` events are ignored. `Group.entries` may be either a list
  of objects or an id-keyed object map.
  """
  @spec busy_intervals(object()) :: {:ok, [Interval.t()]} | {:error, term()}
  def busy_intervals(%{"@type" => "Event"} = event), do: event_interval(event)

  def busy_intervals(%{"@type" => "Group", "entries" => entries}) do
    entries
    |> normalize_entries()
    |> parse_entries()
  end

  def busy_intervals(%{"@type" => type}), do: {:error, {:unsupported, :jscalendar, type}}
  def busy_intervals(_object), do: {:error, {:invalid, :jscalendar, :object}}

  defp normalize_entries(entries) when is_list(entries), do: entries

  defp normalize_entries(entries) when is_map(entries) do
    entries
    |> Enum.sort_by(fn {id, _entry} -> id end)
    |> Enum.map(fn {_id, entry} -> entry end)
  end

  defp normalize_entries(_entries), do: :invalid

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

  defp event_interval(%{"recurrenceRules" => _rules}) do
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

  defp event_interval(%{"start" => _start}),
    do: {:error, {:unsupported, :jscalendar, :floating_time}}

  defp event_interval(_event), do: {:error, {:invalid, :jscalendar, :event}}

  defp parse_local_datetime(<<date::binary-size(10), "T", time::binary-size(8)>>, timezone) do
    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, time} <- Time.from_iso8601(time) do
      resolve_datetime(date, time, timezone)
    end
  end

  defp parse_local_datetime(_value, _timezone), do: {:error, {:invalid, :jscalendar, :start}}

  defp resolve_datetime(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, _before, after_gap} -> {:ok, after_gap}
      {:error, _reason} -> {:error, {:invalid, :jscalendar, :timezone}}
    end
  end

  defp parse_duration(value) when is_binary(value) do
    case Regex.run(~r/^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/, value) do
      nil ->
        {:error, {:invalid, :jscalendar, :duration}}

      captures ->
        captures
        |> tl()
        |> pad_captures()
        |> duration_parts()
    end
  end

  defp parse_duration(_value), do: {:error, {:invalid, :jscalendar, :duration}}

  defp pad_captures(captures), do: captures ++ List.duplicate("", 5 - length(captures))

  defp duration_parts([weeks, days, hours, minutes, seconds]) do
    duration = %{
      days: parse_duration_part(weeks) * 7 + parse_duration_part(days),
      seconds:
        parse_duration_part(hours) * 3_600 + parse_duration_part(minutes) * 60 +
          parse_duration_part(seconds)
    }

    if duration.days > 0 or duration.seconds > 0 do
      {:ok, duration}
    else
      {:ok, %{days: 0, seconds: 0}}
    end
  end

  defp parse_duration_part(""), do: 0
  defp parse_duration_part(value), do: String.to_integer(value)

  defp add_duration(start_at, %{days: 0, seconds: seconds}, _timezone) do
    {:ok, DateTime.add(start_at, seconds, :second)}
  end

  defp add_duration(start_at, %{days: days, seconds: seconds}, timezone) do
    start_date = DateTime.to_date(start_at)
    shifted_date = Date.add(start_date, days)
    local_time = DateTime.to_time(start_at)

    with {:ok, day_shifted} <- resolve_datetime(shifted_date, local_time, timezone) do
      {:ok, DateTime.add(day_shifted, seconds, :second)}
    end
  end

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
