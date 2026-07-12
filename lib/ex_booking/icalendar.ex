defmodule ExBooking.ICalendar do
  @moduledoc """
  iCalendar free/busy normalization.

  `ExBooking.ICalendar` extracts `FREEBUSY` periods from caller-supplied ICS
  text and returns merged UTC busy intervals. It intentionally does not fetch
  calendars, understand provider auth, or implement a full calendar sync
  adapter.

  ## Example

      iex> ics = "FREEBUSY:20260713T090000Z/20260713T093000Z"
      ...> {:ok, [busy]} = ExBooking.ICalendar.free_busy(ics)
      ...> {busy.kind, busy.start_at, busy.end_at}
      {:busy, ~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z]}

  """

  alias ExBooking.Interval

  @typedoc "Raw iCalendar text."
  @type ics :: String.t()

  @doc """
  Extracts `FREEBUSY` periods from iCalendar text.

  Supports comma-separated period values in either `start/end` or
  `start/duration` form. Date-times must be UTC (`YYYYMMDDTHHMMSSZ`). Periods
  marked `FBTYPE=FREE` are validated and excluded from the busy result.
  """
  @spec free_busy(ics()) :: {:ok, [Interval.t()]} | {:error, term()}
  def free_busy(ics) when is_binary(ics) do
    values =
      ics
      |> unfold()
      |> String.split(~r/\r\n|\n|\r/, trim: true)
      |> Enum.filter(&freebusy?/1)
      |> collect_period_values()

    case values do
      {:ok, values} -> parse_periods(values)
      {:error, reason} -> {:error, reason}
    end
  end

  defp unfold(ics), do: String.replace(ics, ~r/\r\n[ \t]|\n[ \t]|\r[ \t]/, "")

  defp freebusy?(line) do
    line
    |> property_name()
    |> Kernel.==("FREEBUSY")
  end

  defp property_name(line) do
    line
    |> String.split(":", parts: 2)
    |> List.first()
    |> String.split(";", parts: 2)
    |> List.first()
    |> String.upcase()
  end

  defp period_values(line) do
    case String.split(line, ":", parts: 2) do
      [property, values] ->
        type = fbtype(property)
        {:ok, Enum.map(String.split(values, ",", trim: true), &{&1, type})}

      _ ->
        {:error, {:invalid, :freebusy, :property}}
    end
  end

  defp collect_period_values(lines) do
    result =
      Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
        case period_values(line) do
          {:ok, values} -> {:cont, {:ok, [values | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, values} -> {:ok, List.flatten(Enum.reverse(values))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fbtype(property) do
    property
    |> String.split(";")
    |> Enum.drop(1)
    |> Enum.find_value(:busy, &fbtype_parameter/1)
  end

  defp fbtype_parameter(parameter) do
    case String.split(parameter, "=", parts: 2) do
      [name, value] -> if String.upcase(name) == "FBTYPE", do: normalize_fbtype(value)
      _ -> nil
    end
  end

  defp normalize_fbtype(value) do
    if String.upcase(value) == "FREE", do: :free, else: :busy
  end

  defp parse_periods(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn {value, type}, {:ok, acc} ->
        case parse_period(value) do
          {:ok, _} when type == :free -> {:cont, {:ok, acc}}
          {:ok, interval} -> {:cont, {:ok, [interval | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, intervals} ->
        {:ok,
         intervals
         |> Enum.reverse()
         |> Interval.merge()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_period(value) do
    case String.split(value, "/", parts: 2) do
      [start_value, "P" <> _ = duration_value] ->
        with {:ok, start_at} <- parse_utc(start_value),
             {:ok, seconds} <- parse_duration(duration_value),
             {:ok, end_at} <- add_duration(start_at, seconds) do
          Interval.new(start_at, end_at, kind: :busy)
        end

      [start_value, end_value] ->
        with {:ok, start_at} <- parse_utc(start_value),
             {:ok, end_at} <- parse_utc(end_value) do
          Interval.new(start_at, end_at, kind: :busy)
        end

      _ ->
        {:error, {:invalid, :freebusy, :period}}
    end
  end

  defp parse_utc(<<date::binary-size(8), "T", time::binary-size(6), "Z">>) do
    with {:ok, date} <- parse_date(date),
         {:ok, time} <- parse_time(time) do
      DateTime.new(date, time, "Etc/UTC")
    end
  end

  defp parse_utc(_), do: {:error, {:unsupported, :freebusy, :datetime}}

  defp parse_duration(value) do
    patterns = [
      {~r/^P(\d+)W$/, [604_800]},
      {~r/^P(\d+)D$/, [86_400]},
      {~r/^P(?:(\d+)D)?T(\d+)H(\d+)M(\d+)S$/, [86_400, 3_600, 60, 1]},
      {~r/^P(?:(\d+)D)?T(\d+)H(\d+)M$/, [86_400, 3_600, 60]},
      {~r/^P(?:(\d+)D)?T(\d+)H$/, [86_400, 3_600]},
      {~r/^P(?:(\d+)D)?T(\d+)M(\d+)S$/, [86_400, 60, 1]},
      {~r/^P(?:(\d+)D)?T(\d+)M$/, [86_400, 60]},
      {~r/^P(?:(\d+)D)?T(\d+)S$/, [86_400, 1]}
    ]

    case Enum.find_value(patterns, &duration_match(&1, value)) do
      seconds when is_integer(seconds) and seconds > 0 -> {:ok, seconds}
      _ -> {:error, {:invalid, :freebusy, :duration}}
    end
  end

  defp duration_match({regex, multipliers}, value) do
    case Regex.run(regex, value) do
      nil ->
        nil

      [_ | captures] ->
        captures
        |> pad_captures(length(multipliers))
        |> Enum.zip(multipliers)
        |> Enum.reduce(0, fn {capture, multiplier}, total ->
          total + parse_duration_part(capture) * multiplier
        end)
    end
  end

  defp pad_captures(captures, size), do: captures ++ List.duplicate("", size - length(captures))

  defp parse_duration_part(""), do: 0
  defp parse_duration_part(value), do: String.to_integer(value)

  defp add_duration(start_at, seconds) do
    {:ok, DateTime.add(start_at, seconds, :second)}
  rescue
    _ -> {:error, {:invalid, :freebusy, :duration}}
  end

  defp parse_date(<<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _ -> {:error, {:invalid, :freebusy, :date}}
    end
  end

  defp parse_time(<<hour::binary-size(2), minute::binary-size(2), second::binary-size(2)>>) do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         {second, ""} <- Integer.parse(second),
         {:ok, time} <- Time.new(hour, minute, second) do
      {:ok, time}
    else
      _ -> {:error, {:invalid, :freebusy, :time}}
    end
  end
end
