defmodule ExBooking.RRule do
  @moduledoc """
  Small RFC 5545 RRULE expander.

  `ExBooking.RRule` supports a narrow dependency-free subset for common daily
  and weekly recurrences: `FREQ`, `INTERVAL`, `COUNT`, UTC `UNTIL`, and weekly
  `BYDAY`. Unsupported rule parts fail explicitly instead of being ignored.

  ## Example

      iex> {:ok, [first, second]} =
      ...>   ExBooking.RRule.expand(
      ...>     "FREQ=DAILY;COUNT=2",
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     30,
      ...>     ~U[2026-07-13 00:00:00Z],
      ...>     ~U[2026-07-15 00:00:00Z]
      ...>   )
      ...>
      ...> {first.start_at, second.start_at}
      {~U[2026-07-13 09:00:00Z], ~U[2026-07-14 09:00:00Z]}

  """

  alias ExBooking.Interval

  @weekdays %{
    "MO" => 1,
    "TU" => 2,
    "WE" => 3,
    "TH" => 4,
    "FR" => 5,
    "SA" => 6,
    "SU" => 7
  }

  @supported ~w(FREQ INTERVAL COUNT UNTIL BYDAY)

  @typedoc "Supported recurrence frequency."
  @type frequency :: :daily | :weekly

  @typedoc "Parsed RRULE subset."
  @type t :: %__MODULE__{
          freq: frequency(),
          interval: pos_integer(),
          count: pos_integer() | nil,
          until: DateTime.t() | nil,
          byday: [1..7] | nil
        }

  @enforce_keys [:freq]
  defstruct [:freq, :count, :until, :byday, interval: 1]

  @doc """
  Parses an RFC 5545 `RRULE` line or value into the supported subset.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(value) when is_binary(value) do
    value
    |> normalize()
    |> split_parts()
    |> parse_parts(%{})
    |> build_rule()
  end

  @doc """
  Expands `rrule` into UTC intervals over `[from, until]`.

  `dtstart` supplies the first occurrence start. `duration_min` supplies each
  occurrence duration. The returned intervals are sorted ascending.
  """
  @spec expand(String.t() | t(), DateTime.t(), pos_integer(), DateTime.t(), DateTime.t()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def expand(rrule, %DateTime{} = dtstart, duration_min, %DateTime{} = from, %DateTime{} = until)
      when is_integer(duration_min) and duration_min > 0 do
    with {:ok, rule} <- coerce_rule(rrule) do
      {:ok, expand_rule(rule, dtstart, duration_min, from, until)}
    end
  end

  defp normalize("RRULE:" <> value), do: value
  defp normalize(value), do: value

  defp split_parts(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.split(&1, "=", parts: 2))
  end

  defp parse_parts(parts, acc) do
    Enum.reduce_while(parts, {:ok, acc}, fn
      [key, value], {:ok, acc} ->
        key = String.upcase(key)

        cond do
          key not in @supported -> {:halt, {:error, {:unsupported, :rrule, key}}}
          Map.has_key?(acc, key) -> {:halt, {:error, {:invalid, :rrule, {:duplicate, key}}}}
          true -> {:cont, {:ok, Map.put(acc, key, value)}}
        end

      _, _ ->
        {:halt, {:error, {:invalid, :rrule, :part}}}
    end)
  end

  defp build_rule({:error, reason}), do: {:error, reason}

  defp build_rule({:ok, %{"FREQ" => freq} = parts}) do
    with {:ok, freq} <- parse_freq(freq),
         {:ok, interval} <- parse_positive(parts["INTERVAL"], 1, :interval),
         {:ok, count} <- parse_optional_positive(parts["COUNT"], :count),
         {:ok, until} <- parse_until(parts["UNTIL"]),
         {:ok, byday} <- parse_byday(parts["BYDAY"], freq) do
      {:ok, %__MODULE__{freq: freq, interval: interval, count: count, until: until, byday: byday}}
    end
  end

  defp build_rule({:ok, _}), do: {:error, {:invalid, :rrule, :freq}}

  defp parse_freq("DAILY"), do: {:ok, :daily}
  defp parse_freq("WEEKLY"), do: {:ok, :weekly}
  defp parse_freq(freq), do: {:error, {:unsupported, :rrule, {:freq, freq}}}

  defp parse_positive(nil, default, _), do: {:ok, default}

  defp parse_positive(value, _, field) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, {:invalid, :rrule, field}}
    end
  end

  defp parse_optional_positive(nil, _), do: {:ok, nil}
  defp parse_optional_positive(value, field), do: parse_positive(value, nil, field)

  defp parse_until(nil), do: {:ok, nil}

  defp parse_until(value) do
    case parse_utc(value) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, _} -> {:error, {:invalid, :rrule, :until}}
    end
  end

  defp parse_byday(nil, _), do: {:ok, nil}
  defp parse_byday(_, :daily), do: {:error, {:unsupported, :rrule, :byday}}

  defp parse_byday(value, :weekly) do
    days =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&Map.get(@weekdays, &1))

    if Enum.all?(days, &is_integer/1) do
      {:ok, Enum.sort(days)}
    else
      {:error, {:invalid, :rrule, :byday}}
    end
  end

  defp coerce_rule(%__MODULE__{} = rule), do: {:ok, rule}
  defp coerce_rule(value) when is_binary(value), do: parse(value)

  defp expand_rule(rule, dtstart, duration_min, from, until) do
    rule
    |> occurrence_stream(dtstart)
    |> Stream.take_while(&within_rule_bounds?(&1, rule, until))
    |> Stream.with_index(1)
    |> Stream.take_while(fn {_, index} -> rule.count == nil or index <= rule.count end)
    |> Stream.map(fn {start_at, _} ->
      Interval.new!(start_at, DateTime.add(start_at, duration_min, :minute), kind: :available)
    end)
    |> Stream.map(&Interval.clip(&1, Interval.new!(from, until)))
    |> Enum.reject(&is_nil/1)
  end

  defp occurrence_stream(%__MODULE__{freq: :daily, interval: interval}, dtstart) do
    Stream.iterate(dtstart, &DateTime.add(&1, interval, :day))
  end

  defp occurrence_stream(%__MODULE__{freq: :weekly, byday: nil, interval: interval}, dtstart) do
    Stream.iterate(dtstart, &DateTime.add(&1, interval * 7, :day))
  end

  defp occurrence_stream(%__MODULE__{freq: :weekly, byday: byday, interval: interval}, dtstart) do
    dtstart
    |> Stream.iterate(&DateTime.add(&1, 1, :day))
    |> Stream.filter(
      &(week_in_interval?(dtstart, &1, interval) and Date.day_of_week(&1) in byday)
    )
  end

  defp week_in_interval?(dtstart, datetime, interval) do
    weeks = div(Date.diff(DateTime.to_date(datetime), DateTime.to_date(dtstart)), 7)
    rem(weeks, interval) == 0
  end

  defp within_rule_bounds?(start_at, rule, horizon_until) do
    DateTime.compare(start_at, horizon_until) == :lt and
      (rule.until == nil or DateTime.compare(start_at, rule.until) != :gt)
  end

  defp parse_utc(<<date::binary-size(8), "T", time::binary-size(6), "Z">>) do
    with {:ok, date} <- parse_date(date),
         {:ok, time} <- parse_time(time) do
      DateTime.new(date, time, "Etc/UTC")
    end
  end

  defp parse_utc(_), do: {:error, :invalid}

  defp parse_date(<<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day) do
      Date.new(year, month, day)
    else
      _ -> {:error, :invalid}
    end
  end

  defp parse_time(<<hour::binary-size(2), minute::binary-size(2), second::binary-size(2)>>) do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         {second, ""} <- Integer.parse(second) do
      Time.new(hour, minute, second)
    else
      _ -> {:error, :invalid}
    end
  end
end
