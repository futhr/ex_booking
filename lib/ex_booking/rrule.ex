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
  alias ExBooking.Occurrence
  alias ExBooking.OccurrenceCursor
  alias ExBooking.OccurrencePage
  alias ExBooking.Temporal
  alias ExBooking.TimeZoneProvider

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

  ## Example

      iex> {:ok, rule} = ExBooking.RRule.parse("FREQ=WEEKLY;BYDAY=MO,WE")
      ...> {rule.freq, rule.byday}
      {:weekly, [1, 3]}

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

  ## Example

      iex> {:ok, [first]} =
      ...>   ExBooking.RRule.expand(
      ...>     "FREQ=DAILY;COUNT=1",
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     30,
      ...>     ~U[2026-07-13 00:00:00Z],
      ...>     ~U[2026-07-14 00:00:00Z]
      ...>   )
      ...>
      ...> first.end_at
      ~U[2026-07-13 09:30:00Z]

  """
  @spec expand(String.t() | t(), DateTime.t(), pos_integer(), DateTime.t(), DateTime.t()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def expand(rrule, %DateTime{} = dtstart, duration_min, %DateTime{} = from, %DateTime{} = until) do
    with :ok <- validate_datetimes([dtstart, from, until]),
         :ok <- validate_expand_inputs(duration_min, from, until),
         {:ok, rule} <- coerce_rule(rrule),
         {:ok, local_until} <- local_horizon(until, dtstart.time_zone) do
      {:ok, expand_rule(rule, dtstart, duration_min, {from, until, local_until})}
    end
  end

  def expand(_, _, _, _, _), do: {:error, {:invalid, :rrule, :arguments}}

  @doc """
  Enumerates original starts with explicit time-zone inputs and finite work.

  Uses the options and native page/cursor values documented by
  `ExBooking.occurrences/3`. Dates in gaps are skipped without consuming COUNT;
  later fold dates choose the first instant. A supplied second-fold DTSTART
  retains its actual instant. Cursor validation replays the prefix within
  `:work_limit`; changing the query basis returns a stale-cursor error.

  ## Example

      iex> {:ok, page} =
      ...>   ExBooking.RRule.occurrences(
      ...>     "FREQ=DAILY;COUNT=1",
      ...>     ~U[2026-07-13 06:00:00Z],
      ...>     from: ~U[2026-07-13 05:55:00Z],
      ...>     until: ~U[2026-07-13 07:00:00Z],
      ...>     time_zone_database: Calendar.UTCOnlyTimeZoneDatabase,
      ...>     time_zone_basis: "utc-v1"
      ...>   )
      ...>
      ...> hd(page.occurrences).starts_at
      ~U[2026-07-13 06:00:00Z]
  """
  @spec occurrences(String.t() | t(), DateTime.t(), keyword()) ::
          {:ok, OccurrencePage.t()} | {:error, term()}
  def occurrences(rule, dtstart, opts) do
    with {:ok, opts} <- validate_occurrence_options(opts),
         :ok <- validate_occurrence_rule_shape(rule),
         {:ok, rule} <- coerce_rule(rule),
         :ok <- validate_occurrence_datetimes(rule, dtstart, opts),
         {:ok, start, resolution} <- resolve_occurrence_start(dtstart, opts.time_zone_database),
         {:ok, basis, last_offset} <- occurrence_query(rule, start, opts),
         :ok <- validate_occurrence_cursor(opts.cursor, basis) do
      state = %{
        basis: basis,
        start_resolution: resolution,
        offset: first_occurrence_offset(rule, start),
        last_offset: last_offset,
        count: 0,
        previous: nil,
        work: 0,
        results: [],
        returned: 0,
        cursor: opts.cursor,
        ready: is_nil(opts.cursor),
        limit: opts.limit,
        work_limit: opts.work_limit
      }

      enumerate_occurrences(state)
    end
  end

  defp validate_occurrence_options(opts) do
    keys = [:from, :until, :time_zone_database, :time_zone_basis, :limit, :work_limit, :cursor]

    if is_list(opts) and Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in keys)) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) do
      options = Map.merge(%{limit: 128, work_limit: 4096, cursor: nil}, Map.new(opts))

      with :ok <- validate_occurrence_option(options, :limit, &(&1 in 1..1024)),
           :ok <- validate_occurrence_option(options, :work_limit, &(&1 in 1..100_000)),
           :ok <- validate_occurrence_option(options, :time_zone_basis, &valid_time_zone_basis?/1),
           :ok <-
             validate_occurrence_option(options, :time_zone_database, &time_zone_database?/1) do
        {:ok, options}
      end
    else
      occurrence_error(:options)
    end
  end

  defp validate_occurrence_option(options, key, valid?) do
    if valid?.(Map.get(options, key)), do: :ok, else: occurrence_error(key)
  end

  defp valid_time_zone_basis?(basis),
    do: is_binary(basis) and byte_size(basis) in 1..256 and String.valid?(basis)

  defp time_zone_database?(%TimeZoneProvider{} = provider), do: TimeZoneProvider.valid?(provider)

  defp time_zone_database?(database),
    do:
      is_atom(database) and
        Code.ensure_loaded?(database) and
        function_exported?(database, :time_zone_periods_from_wall_datetime, 2) and
        function_exported?(database, :time_zone_period_from_utc_iso_days, 2)

  defp validate_occurrence_rule_shape(rule) when is_binary(rule) do
    if byte_size(rule) <= 4096 and String.valid?(rule),
      do: :ok,
      else: occurrence_error(:rule_size)
  end

  defp validate_occurrence_rule_shape(%__MODULE__{} = rule) do
    shape = Map.keys(rule) |> Enum.sort()
    expected = Map.keys(%__MODULE__{freq: :daily}) |> Enum.sort()

    if shape == expected and
         (is_nil(rule.byday) or (is_list(rule.byday) and length(rule.byday) <= 7)),
       do: :ok,
       else: occurrence_error(:arguments)
  end

  defp validate_occurrence_rule_shape(_), do: occurrence_error(:arguments)

  defp validate_occurrence_datetimes(rule, dtstart, opts) do
    horizon = [Map.get(opts, :from), Map.get(opts, :until)]

    if occurrence_datetime?(dtstart) and Enum.all?(horizon, &occurrence_datetime?/1) and
         (is_nil(rule.until) or occurrence_until?(rule.until)) and
         DateTime.compare(opts.from, opts.until) == :lt do
      :ok
    else
      occurrence_error(:arguments)
    end
  end

  defp occurrence_datetime?(%DateTime{calendar: Calendar.ISO, year: year} = value),
    do:
      Temporal.datetime?(value) and year in 0..9999 and
        abs(value.utc_offset) <= 86_400 and abs(value.std_offset) <= 86_400 and
        abs(value.utc_offset + value.std_offset) <= 86_400

  defp occurrence_datetime?(_), do: false

  defp occurrence_until?(%DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0} = value),
    do: occurrence_datetime?(value)

  defp occurrence_until?(_), do: false

  defp resolve_occurrence_start(start, database) do
    nominal = DateTime.to_naive(start)

    case TimeZoneProvider.from_naive(nominal, start.time_zone, database) do
      {:ok, actual} ->
        match_occurrence_start(start, [{actual, :unique}])

      {:ambiguous, first, second} ->
        match_occurrence_start(start, [{first, :first_fold}, {second, :second_fold}])

      _ ->
        occurrence_error(:dtstart)
    end
  end

  defp match_occurrence_start(start, candidates) do
    case Enum.find(candidates, fn {actual, _} ->
           DateTime.compare(start, actual) == :eq and
             start.utc_offset + start.std_offset == actual.utc_offset + actual.std_offset
         end) do
      {actual, resolution} -> {:ok, %{actual | microsecond: start.microsecond}, resolution}
      nil -> occurrence_error(:dtstart)
    end
  end

  defp occurrence_query(rule, start, opts) do
    with {:ok, from} <- occurrence_utc(opts.from),
         {:ok, until} <- occurrence_utc(opts.until),
         {:ok, local_until} <-
           TimeZoneProvider.shift_zone(until, start.time_zone, opts.time_zone_database),
         true <- occurrence_datetime?(local_until) do
      basis = %{
        rule: rule,
        dtstart: start,
        from: from,
        until: until,
        time_zone_database: opts.time_zone_database,
        time_zone_basis: opts.time_zone_basis
      }

      {:ok, basis, Date.diff(DateTime.to_date(local_until), DateTime.to_date(start))}
    else
      _ -> occurrence_error(:arguments)
    end
  end

  defp occurrence_utc(value) do
    case DateTime.shift_zone(value, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase) do
      {:ok, utc} when utc.year in 0..9999 -> {:ok, utc}
      _ -> occurrence_error(:arguments)
    end
  end

  defp validate_occurrence_cursor(nil, _), do: :ok

  defp validate_occurrence_cursor(%OccurrenceCursor{} = cursor, basis) do
    expected = Map.keys(%OccurrenceCursor{basis: nil, next_offset_days: 0, emitted_count: 0})

    cond do
      Enum.sort(Map.keys(cursor)) != Enum.sort(expected) ->
        occurrence_error(:cursor)

      not is_map(cursor.basis) or not is_integer(cursor.next_offset_days) or
        cursor.next_offset_days < 0 or not is_integer(cursor.emitted_count) or
          cursor.emitted_count < 0 ->
        occurrence_error(:cursor)

      cursor.basis != basis ->
        {:error, {:stale, :occurrences, :cursor_basis}}

      true ->
        :ok
    end
  end

  defp validate_occurrence_cursor(_, _), do: occurrence_error(:cursor)

  defp enumerate_occurrences(state) do
    with {:ok, state} <- verify_occurrence_position(state) do
      consider_occurrence_position(state)
    end
  end

  defp verify_occurrence_position(%{ready: true} = state), do: {:ok, state}

  defp verify_occurrence_position(state) do
    cond do
      state.offset > state.cursor.next_offset_days ->
        occurrence_error(:cursor)

      state.offset == state.cursor.next_offset_days ->
        if state.count == state.cursor.emitted_count,
          do: {:ok, %{state | ready: true}},
          else: occurrence_error(:cursor)

      true ->
        {:ok, state}
    end
  end

  defp consider_occurrence_position(state) do
    cond do
      state.offset > state.last_offset or
          (state.basis.rule.count != nil and state.count >= state.basis.rule.count) ->
        finish_occurrence_page(state)

      state.work >= state.work_limit ->
        {:error, {:limit, :occurrences, :work}}

      true ->
        resolve_occurrence_position(%{state | work: state.work + 1})
    end
  end

  defp resolve_occurrence_position(state) do
    start = state.basis.dtstart
    date = Date.add(DateTime.to_date(start), state.offset)

    resolved =
      if state.offset == 0 do
        {:ok, start, state.start_resolution}
      else
        resolve_occurrence_date(date, start, state.basis.time_zone_database)
      end

    case resolved do
      :gap -> advance_occurrence_position(state)
      {:ok, datetime, resolution} -> accept_occurrence_position(state, datetime, resolution)
      {:error, _} = error -> error
    end
  end

  defp resolve_occurrence_date(date, start, database) do
    {:ok, nominal} = NaiveDateTime.new(date, DateTime.to_time(start))

    case TimeZoneProvider.from_naive(nominal, start.time_zone, database) do
      {:ok, datetime} -> {:ok, datetime, :unique}
      {:ambiguous, first, _} -> {:ok, first, :first_fold}
      {:gap, _, _} -> :gap
      :gap -> :gap
      {:error, _} -> occurrence_error(:arguments)
    end
  end

  defp accept_occurrence_position(state, datetime, resolution) do
    with {:ok, utc} <- occurrence_utc(datetime) do
      cond do
        state.previous != nil and DateTime.compare(utc, state.previous) != :gt ->
          occurrence_error(:time_zone_order)

        DateTime.compare(utc, state.basis.until) != :lt or
            (state.basis.rule.until != nil and
               DateTime.compare(utc, state.basis.rule.until) == :gt) ->
          finish_occurrence_page(state)

        true ->
          retain_occurrence_position(state, datetime, utc, resolution)
      end
    end
  end

  defp retain_occurrence_position(state, datetime, utc, resolution) do
    state = %{state | count: state.count + 1, previous: utc}

    state =
      if state.ready and DateTime.compare(utc, state.basis.from) != :lt do
        occurrence = %Occurrence{
          nominal: DateTime.to_naive(datetime),
          starts_at: utc,
          ordinal: state.count,
          resolution: resolution
        }

        %{state | results: [occurrence | state.results], returned: state.returned + 1}
      else
        state
      end

    if state.returned == state.limit do
      offset = next_occurrence_offset(state.basis.rule, state.basis.dtstart, state.offset)

      cursor = occurrence_next_cursor(state, offset)

      {:ok, %OccurrencePage{occurrences: Enum.reverse(state.results), next_cursor: cursor}}
    else
      advance_occurrence_position(state)
    end
  end

  defp advance_occurrence_position(state) do
    offset = next_occurrence_offset(state.basis.rule, state.basis.dtstart, state.offset)
    enumerate_occurrences(%{state | offset: offset})
  end

  defp occurrence_next_cursor(state, offset) do
    if offset > state.last_offset or
         (state.basis.rule.count != nil and state.count >= state.basis.rule.count) do
      nil
    else
      %OccurrenceCursor{basis: state.basis, next_offset_days: offset, emitted_count: state.count}
    end
  end

  defp finish_occurrence_page(%{ready: false}), do: occurrence_error(:cursor)

  defp finish_occurrence_page(state),
    do: {:ok, %OccurrencePage{occurrences: Enum.reverse(state.results)}}

  defp first_occurrence_offset(%{byday: nil}, _), do: 0

  defp first_occurrence_offset(rule, start) do
    monday = 1 - Date.day_of_week(DateTime.to_date(start))

    Enum.find_value(rule.byday, monday + rule.interval * 7 + hd(rule.byday) - 1, fn weekday ->
      offset = monday + weekday - 1
      if offset >= 0, do: offset
    end)
  end

  defp next_occurrence_offset(%{freq: :daily, interval: interval}, _, offset),
    do: offset + interval

  defp next_occurrence_offset(%{byday: nil, interval: interval}, _, offset),
    do: offset + interval * 7

  defp next_occurrence_offset(rule, start, offset) do
    monday = 1 - Date.day_of_week(DateTime.to_date(start))
    block = div(offset - monday, rule.interval * 7)
    beginning = monday + block * rule.interval * 7

    Enum.find_value(rule.byday, beginning + rule.interval * 7 + hd(rule.byday) - 1, fn weekday ->
      candidate = beginning + weekday - 1
      if candidate > offset, do: candidate
    end)
  end

  defp occurrence_error(reason), do: {:error, {:invalid, :occurrences, reason}}

  defp normalize("RRULE:" <> value), do: value
  defp normalize(value), do: value

  defp split_parts(""), do: []

  defp split_parts(value) do
    value
    |> String.split(";")
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
         :ok <- validate_bounds(count, until),
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
      |> String.split(",")
      |> Enum.map(&Map.get(@weekdays, &1))

    if days != [] and Enum.all?(days, &is_integer/1) do
      unique_days = Enum.uniq(days)
      {:ok, Enum.sort(unique_days)}
    else
      {:error, {:invalid, :rrule, :byday}}
    end
  end

  defp coerce_rule(%__MODULE__{} = rule), do: validate_rule(rule)
  defp coerce_rule(value) when is_binary(value), do: parse(value)
  defp coerce_rule(_), do: {:error, {:invalid, :rrule, :arguments}}

  defp validate_rule(%__MODULE__{} = rule) do
    with :ok <- validate_frequency(rule.freq),
         :ok <- validate_positive(rule.interval, :interval),
         :ok <- validate_optional_positive(rule.count, :count),
         :ok <- validate_optional_datetime(rule.until),
         :ok <- validate_bounds(rule.count, rule.until),
         {:ok, byday} <- validate_rule_byday(rule.byday, rule.freq) do
      {:ok, %{rule | byday: byday}}
    end
  end

  defp validate_bounds(nil, _), do: :ok
  defp validate_bounds(_, nil), do: :ok
  defp validate_bounds(_, _), do: {:error, {:invalid, :rrule, :count_and_until}}

  defp validate_frequency(freq) when freq in [:daily, :weekly], do: :ok
  defp validate_frequency(freq), do: {:error, {:unsupported, :rrule, {:freq, freq}}}

  defp validate_positive(value, _) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(_, field), do: {:error, {:invalid, :rrule, field}}

  defp validate_optional_positive(nil, _), do: :ok
  defp validate_optional_positive(value, field), do: validate_positive(value, field)

  defp validate_optional_datetime(nil), do: :ok

  defp validate_optional_datetime(value) do
    if Temporal.datetime?(value), do: :ok, else: {:error, {:invalid, :rrule, :until}}
  end

  defp validate_datetimes(values) do
    if Enum.all?(values, &Temporal.datetime?/1),
      do: :ok,
      else: {:error, {:invalid, :rrule, :arguments}}
  end

  defp validate_rule_byday(nil, _), do: {:ok, nil}
  defp validate_rule_byday(_, :daily), do: {:error, {:unsupported, :rrule, :byday}}

  defp validate_rule_byday(byday, :weekly) when is_list(byday) and byday != [] do
    if Enum.all?(byday, &(is_integer(&1) and &1 in 1..7)) do
      unique_days = Enum.uniq(byday)
      {:ok, Enum.sort(unique_days)}
    else
      {:error, {:invalid, :rrule, :byday}}
    end
  end

  defp validate_rule_byday(_, :weekly), do: {:error, {:invalid, :rrule, :byday}}

  defp validate_expand_inputs(duration_min, from, until) do
    cond do
      not is_integer(duration_min) or duration_min <= 0 ->
        {:error, {:invalid, :rrule, :arguments}}

      DateTime.compare(from, until) != :lt ->
        {:error, {:invalid, :horizon, :not_increasing}}

      true ->
        :ok
    end
  end

  defp local_horizon(until, timezone) do
    case DateTime.shift_zone(until, timezone) do
      {:ok, local_until} -> {:ok, local_until}
      {:error, _} -> {:error, {:invalid, :rrule, :arguments}}
    end
  end

  defp expand_rule(rule, dtstart, duration_min, {from, until, local_until}) do
    utc_from = DateTime.shift_zone!(from, "Etc/UTC")
    utc_until = DateTime.shift_zone!(until, "Etc/UTC")

    rule
    |> occurrence_stream(dtstart, local_until)
    |> Stream.reject(&is_nil/1)
    |> Stream.take_while(&within_rule_bounds?(&1, rule, until))
    |> Stream.with_index(1)
    |> Stream.take_while(fn {_, index} -> rule.count == nil or index <= rule.count end)
    |> Stream.map(fn {start_at, _} ->
      start_at = DateTime.shift_zone!(start_at, "Etc/UTC")
      Interval.new!(start_at, DateTime.add(start_at, duration_min, :minute), kind: :available)
    end)
    |> Stream.map(&Interval.clip(&1, Interval.new!(utc_from, utc_until)))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  defp occurrence_stream(rule, dtstart, local_until) do
    last_date = DateTime.to_date(local_until)
    last_offset = Date.diff(last_date, DateTime.to_date(dtstart))

    rule
    |> occurrence_offsets(dtstart)
    |> Stream.take_while(&(&1 <= last_offset))
    |> Stream.map(&calendar_occurrence(dtstart, &1))
  end

  defp occurrence_offsets(rule, dtstart) do
    Stream.iterate(
      first_occurrence_offset(rule, dtstart),
      &next_occurrence_offset(rule, dtstart, &1)
    )
  end

  defp calendar_occurrence(dtstart, 0), do: dtstart

  defp calendar_occurrence(dtstart, day_offset) do
    date = Date.add(DateTime.to_date(dtstart), day_offset)

    case DateTime.new(date, DateTime.to_time(dtstart), dtstart.time_zone) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _} -> first
      {:gap, _, _} -> nil
    end
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
