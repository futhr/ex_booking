defmodule ExBooking.ICalendar do
  @moduledoc """
  Dependency-free iCalendar free/busy normalization helpers.

  The supported surface is intentionally narrow: unfolded RFC 5545 content is
  scanned for `FREEBUSY` properties, whose period values are normalized into
  UTC `ExBooking.Interval` structs with `kind: :busy`. Vendor parameters such as
  `FBTYPE` are accepted and ignored; unsupported date/time forms fail
  explicitly.
  """

  alias ExBooking.Interval

  @typedoc "Raw iCalendar text."
  @type ics :: String.t()

  @doc """
  Extracts `FREEBUSY` periods from iCalendar text.

  Supports comma-separated period values in either `start/end` or
  `start/duration` form. Date-times must be UTC (`YYYYMMDDTHHMMSSZ`).
  """
  @spec free_busy(ics()) :: {:ok, [Interval.t()]} | {:error, term()}
  def free_busy(ics) when is_binary(ics) do
    ics
    |> unfold()
    |> String.split(~r/\r\n|\n|\r/, trim: true)
    |> Enum.filter(&freebusy?/1)
    |> Enum.flat_map(&period_values/1)
    |> parse_periods()
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
      [_name, values] -> String.split(values, ",", trim: true)
      _invalid -> []
    end
  end

  defp parse_periods(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case parse_period(value) do
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
      [start_value, "P" <> _duration = duration_value] ->
        with {:ok, start_at} <- parse_utc(start_value),
             {:ok, seconds} <- parse_duration(duration_value) do
          Interval.new(start_at, DateTime.add(start_at, seconds, :second), kind: :busy)
        end

      [start_value, end_value] ->
        with {:ok, start_at} <- parse_utc(start_value),
             {:ok, end_at} <- parse_utc(end_value) do
          Interval.new(start_at, end_at, kind: :busy)
        end

      _invalid ->
        {:error, {:invalid, :freebusy, :period}}
    end
  end

  defp parse_utc(<<date::binary-size(8), "T", time::binary-size(6), "Z">>) do
    with {:ok, date} <- parse_date(date),
         {:ok, time} <- parse_time(time) do
      DateTime.new(date, time, "Etc/UTC")
    end
  end

  defp parse_utc(_value), do: {:error, {:unsupported, :freebusy, :datetime}}

  defp parse_duration(value) do
    case Regex.run(~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/, value) do
      nil ->
        {:error, {:invalid, :freebusy, :duration}}

      captures ->
        seconds =
          captures
          |> tl()
          |> pad_captures()
          |> Enum.zip([86_400, 3_600, 60, 1])
          |> Enum.reduce(0, fn {capture, multiplier}, total ->
            total + parse_duration_part(capture) * multiplier
          end)

        if seconds > 0, do: {:ok, seconds}, else: {:error, {:invalid, :freebusy, :duration}}
    end
  end

  defp pad_captures(captures), do: captures ++ List.duplicate("", 4 - length(captures))

  defp parse_duration_part(""), do: 0
  defp parse_duration_part(value), do: String.to_integer(value)

  defp parse_date(<<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day) do
      Date.new(year, month, day)
    else
      _invalid -> {:error, {:invalid, :freebusy, :date}}
    end
  end

  defp parse_time(<<hour::binary-size(2), minute::binary-size(2), second::binary-size(2)>>) do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         {second, ""} <- Integer.parse(second) do
      Time.new(hour, minute, second)
    else
      _invalid -> {:error, {:invalid, :freebusy, :time}}
    end
  end
end
