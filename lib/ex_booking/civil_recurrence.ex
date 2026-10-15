defmodule ExBooking.CivilRecurrence do
  @moduledoc """
  Enumerates a weekday/time pattern over an explicit finite local-date span.

  Call `occurrences/3` directly or use `ExBooking.civil_occurrences/3`. Success
  is `{:ok, points}`, where `points` is a strictly UTC-ordered list of
  `ExBooking.CivilOccurrence` values: original local labels and original instants,
  without durations or booking availability. The 1–366 local dates and half-open
  UTC window are independent inputs; all eight options are explicit.

  For an immutable `ExBooking.TimeZoneProvider`, civil resolution prefers
  `c:ExBooking.TimeZoneProvider.resolve_civil/3` when exported. It can supply a
  complete ambiguity list of 2–732 alternatives. Refusal, malformed output or an
  implementation fault never retries the legacy resolver. When absent, the
  required resolver is used once; `Calendar.TimeZoneDatabase` modules retain
  their unique/twofold interface. Existing helpers and original RRULE enumeration
  never select the optional callback.

  Within the work budget, every alternative round-trips through the same database
  before gap/fold policy and UTC filtering, including alternatives that policy
  will discard. `:first`/`:second` selects positions 1/2; `:both` retains the whole
  set. Local positions 1/2 use `:first_fold`/`:second_fold`, and later positions
  use `{:fold, index}`. They are not recurrence ordinals and are never renumbered
  after filtering. Rejection applies even outside the UTC window; first policy
  never substitutes another fold. Gaps are skipped or rejected, never snapped.

  The whole query permits at most 366 selected-label resolutions and 732
  round-trip localizations. A new label's complete candidate count must fit the
  remaining localization budget before any of that label's localizations run;
  otherwise return `{:error, {:limit, :civil_occurrences, :work}}`. Gaps consume
  no localizations. Policy and filtering do not refund work. No partial or
  truncated result is returned; the caller owns splitting a larger query and
  combining its results. These finite counts do not impose a callback deadline.

  Civil DateTimes permit `:utc_offset` and `:std_offset` each within
  `-93_599..93_599` seconds and their total within `-89_999..93_599` seconds.
  Provider callbacks are checked directly under that profile;
  `ExBooking.TimeZoneProvider.from_naive/3` and
  `ExBooking.TimeZoneProvider.shift_zone/3` retain their component/total
  `-86_400..86_400` bounds. Callback error payloads become fixed query errors;
  implementation exceptions propagate as programming errors.

  There is no DTSTART, RRULE, COUNT, global ordinal or cursor. Empty output covers
  only the supplied dates, not all later dates. Consumers own immutable database
  custody, wider ordering/deduplication, durable identity and downstream authority.
  No library state, process, clock read or I/O is owned by this calculation.
  """

  alias ExBooking.CivilOccurrence
  alias ExBooking.Temporal
  alias ExBooking.TimeZoneProvider

  @keys ~w(days weekdays from until time_zone time_zone_database gap_policy fold_policy)a
  @date_keys Enum.sort(Map.keys(struct(Date)))
  @time_keys Enum.sort(Map.keys(struct(Time)))
  @datetime_keys Enum.sort(Map.keys(struct(DateTime)))

  @doc """
  Returns all matching civil points in strictly increasing UTC order.

  `time` must be an exact ISO `Time` with whole seconds and microsecond precision
  `{0, 0}`. `first_date` must be an exact ISO `Date` in years 0000–9999. Extra
  native fields and alternate calendars refuse. All eight options are required
  exactly once in a proper keyword list; missing, duplicate or unknown keys
  refuse before timezone callbacks. There are no defaults.

  | Option | Required value |
  | --- | --- |
  | `:days` | Integer 1–366; the inclusive span from `first_date` must remain in years 0000–9999. |
  | `:weekdays` | Nonempty ascending unique list of ISO weekdays 1–7. |
  | `:from` | Exact ISO `DateTime` at the inclusive UTC query boundary. |
  | `:until` | Exact ISO `DateTime` at the exclusive UTC query boundary; strictly later than `:from`. |
  | `:time_zone` | Valid UTF-8 zone name of 1–256 bytes. |
  | `:time_zone_database` | Explicit `Calendar.TimeZoneDatabase` module or immutable `ExBooking.TimeZoneProvider`. |
  | `:gap_policy` | `:skip` or `:reject`. |
  | `:fold_policy` | `:first`, `:second`, `:both` or `:reject`; unique labels remain unique. |

  Query boundaries and resolved DateTimes must have years 0000–9999, UTF-8
  timezone names of 1–256 bytes, abbreviations of 0–256 bytes and offsets within
  the civil profile documented above. Boundaries normalize from their supplied
  fields and total offsets to canonical UTC, even when already named `Etc/UTC`,
  preserving fractional values and native microsecond precision.
  Both normalized endpoints and retained instants must remain in years 0000–9999.
  Returned points satisfy `from <= starts_at < until` without clipping either
  their instant or nominal label.

  Every alternative of a fold must round-trip correctly before selection, even
  when only one would pass the UTC filter. Optional `c:ExBooking.TimeZoneProvider.resolve_civil/3`
  can return a complete 2–732-candidate ambiguity list. Later local positions
  retain `{:fold, index}` tags rather than inventing recurrence ordinals. Results contain at most 732
  `ExBooking.CivilOccurrence` values; duplicate UTC instants refuse rather than
  being merged. Empty output means no matching point in this finite local span.
  There are at most 366 local resolutions and 732 round-trip localizations.
  A complete label that would exceed the remaining localization budget returns
  `{:error, {:limit, :civil_occurrences, :work}}` before localizing any of its
  alternatives. Policy/filtering does not refund work; no partial result is returned.

  Invalid input returns `{:error, {:invalid, :civil_occurrences, field}}`, with
  field one of `:options`, `:time`, `:first_date`, `:days`, `:weekdays`, `:from`,
  `:until`, `:horizon`, `:time_zone`, `:time_zone_database`, `:gap_policy`,
  `:fold_policy`, `:time_zone_result` or `:coordinate_range`. Refused/malformed
  callback results use `:time_zone_result`; unsupported UTC coordinates use
  `:coordinate_range`. Rejected gaps and folds return
  `{:error, {:gap, :civil_occurrences}}` and
  `{:error, {:ambiguous, :civil_occurrences}}`. No partial list or callback error
  payload is returned. Callback implementation exceptions propagate.

  ## Examples

      iex> {:ok, [point]} =
      ...>   ExBooking.CivilRecurrence.occurrences(
      ...>     ~T[09:00:00],
      ...>     ~D[2026-07-13],
      ...>     days: 1,
      ...>     weekdays: [1],
      ...>     from: ~U[2026-07-13 00:00:00Z],
      ...>     until: ~U[2026-07-14 00:00:00Z],
      ...>     time_zone: "Etc/UTC",
      ...>     time_zone_database: Calendar.UTCOnlyTimeZoneDatabase,
      ...>     gap_policy: :skip,
      ...>     fold_policy: :first
      ...>   )
      ...>
      ...> point.starts_at
      ~U[2026-07-13 09:00:00Z]

      iex> ExBooking.CivilRecurrence.occurrences(~T[09:00:00], ~D[2026-07-13], [])
      {:error, {:invalid, :civil_occurrences, :options}}
  """
  @spec occurrences(term(), term(), term()) ::
          {:ok, [CivilOccurrence.t()]} | {:error, term()}
  def occurrences(time, first_date, opts) do
    with {:ok, opts} <- options(opts, %{}),
         :ok <- require_field(time?(time), :time),
         :ok <- require_field(date?(first_date), :first_date),
         :ok <- validate(opts, first_date),
         {:ok, from} <- utc(opts.from),
         {:ok, until} <- utc(opts.until),
         :ok <- require_field(DateTime.compare(from, until) == :lt, :horizon) do
      opts = %{opts | from: from, until: until}

      enumerate(time, first_date, opts)
    end
  end

  defp enumerate(time, first_date, opts) do
    result =
      Enum.reduce_while(0..(opts.days - 1), {:ok, [], 732}, fn offset, {:ok, points, remaining} ->
        case selected(Date.add(first_date, offset), time, opts, remaining) do
          {:ok, values, used} -> {:cont, {:ok, values ++ points, remaining - used}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, points, _} -> ordered({:ok, points})
      error -> error
    end
  end

  defp options([], opts) when map_size(opts) == 8, do: {:ok, opts}

  defp options([{key, value} | tail], opts) when key in @keys and map_size(opts) < 8 do
    if Map.has_key?(opts, key),
      do: invalid(:options),
      else: options(tail, Map.put(opts, key, value))
  end

  defp options(_, _), do: invalid(:options)

  defp validate(opts, date) do
    with :ok <- require_field(is_integer(opts.days) and opts.days in 1..366, :days),
         :ok <- require_field(Date.diff(~D[9999-12-31], date) >= opts.days - 1, :days),
         :ok <- require_field(weekdays?(opts.weekdays, 0, 0), :weekdays),
         :ok <- require_field(datetime?(opts.from), :from),
         :ok <- require_field(datetime?(opts.until), :until),
         :ok <- require_field(text?(opts.time_zone), :time_zone),
         :ok <- require_field(database?(opts.time_zone_database), :time_zone_database),
         :ok <- require_field(opts.gap_policy in [:skip, :reject], :gap_policy) do
      require_field(opts.fold_policy in [:first, :second, :both, :reject], :fold_policy)
    end
  end

  defp selected(date, time, opts, remaining) do
    if Date.day_of_week(date) in opts.weekdays do
      {:ok, nominal} = NaiveDateTime.new(date, time)

      with {:ok, values} <- resolve(nominal, opts),
           used = work(values),
           :ok <- work_budget(used, remaining),
           {:ok, values} <- round_trips(values, nominal, opts),
           {:ok, values} <- policy(values, opts) do
        {:ok, points(values, nominal, opts), used}
      end
    else
      {:ok, [], 0}
    end
  end

  defp points(values, nominal, opts) do
    for {instant, resolution} <- values,
        DateTime.compare(instant, opts.from) != :lt,
        DateTime.compare(instant, opts.until) == :lt,
        do: %CivilOccurrence{nominal: nominal, starts_at: instant, resolution: resolution}
  end

  defp resolve(nominal, opts) do
    case opts.time_zone_database do
      %TimeZoneProvider{module: module, context: context} ->
        if function_exported?(module, :resolve_civil, 3),
          do: resolution(module.resolve_civil(nominal, opts.time_zone, context), true),
          else: resolution(module.resolve(nominal, opts.time_zone, context), false)

      database ->
        result =
          case DateTime.from_naive(nominal, opts.time_zone, database) do
            {:gap, _, _} -> :gap
            result -> result
          end

        resolution(result, false)
    end
  end

  defp resolution(:gap, _), do: {:ok, :gap}
  defp resolution({:ok, value}, _), do: {:ok, [{value, :unique}]}

  defp resolution({:ambiguous, first, second}, _),
    do: {:ok, [{first, :first_fold}, {second, :second_fold}]}

  defp resolution({:ambiguous, candidates}, true), do: alternatives(candidates, 1, [])
  defp resolution(_, _), do: invalid(:time_zone_result)

  defp alternatives([], index, reversed) when index in 3..733,
    do: {:ok, Enum.reverse(reversed)}

  defp alternatives([value | rest], index, reversed) when index <= 732,
    do: alternatives(rest, index + 1, [{value, fold_position(index)} | reversed])

  defp alternatives(_, _, _), do: invalid(:time_zone_result)
  defp fold_position(1), do: :first_fold
  defp fold_position(2), do: :second_fold
  defp fold_position(index), do: {:fold, index}

  defp work(:gap), do: 0
  defp work(values), do: length(values)
  defp work_budget(used, remaining) when used <= remaining, do: :ok
  defp work_budget(_, _), do: {:error, {:limit, :civil_occurrences, :work}}

  defp round_trips(:gap, _, _), do: {:ok, :gap}

  defp round_trips(values, nominal, opts) do
    Enum.reduce_while(values, {:ok, []}, fn {value, resolution}, {:ok, points} ->
      with :ok <- require_field(matches?(value, nominal, opts.time_zone), :time_zone_result),
           {:ok, instant} <- utc(value),
           {:ok, local} <- localize(instant, opts),
           :ok <-
             require_field(
               matches?(local, nominal, opts.time_zone) and
                 DateTime.compare(local, instant) == :eq and
                 local.microsecond == value.microsecond,
               :time_zone_result
             ) do
        {:cont, {:ok, [{instant, resolution} | points]}}
      else
        error -> {:halt, error}
      end
    end)
    |> resolution_order()
  end

  defp resolution_order({:ok, reversed}) do
    values = Enum.reverse(reversed)

    if increasing?(Enum.map(values, &elem(&1, 0))),
      do: {:ok, values},
      else: invalid(:time_zone_result)
  end

  defp resolution_order(error), do: error

  defp localize(instant, opts) do
    result =
      case opts.time_zone_database do
        %TimeZoneProvider{module: module, context: context} ->
          module.localize(instant, opts.time_zone, context)

        database ->
          DateTime.shift_zone(instant, opts.time_zone, database)
      end

    case result do
      {:ok, value} -> {:ok, value}
      _ -> invalid(:time_zone_result)
    end
  end

  defp policy(:gap, %{gap_policy: :skip}), do: {:ok, []}
  defp policy(:gap, _), do: {:error, {:gap, :civil_occurrences}}
  defp policy([{_, :unique}] = values, _), do: {:ok, values}
  defp policy(values, %{fold_policy: :both}), do: {:ok, values}
  defp policy([first | _], %{fold_policy: :first}), do: {:ok, [first]}
  defp policy([_, second | _], %{fold_policy: :second}), do: {:ok, [second]}
  defp policy(_, _), do: {:error, {:ambiguous, :civil_occurrences}}

  defp ordered({:ok, points}) do
    points = Enum.sort_by(points, &DateTime.to_unix(&1.starts_at, :microsecond))

    if increasing?(Enum.map(points, & &1.starts_at)),
      do: {:ok, points},
      else: invalid(:time_zone_result)
  end

  defp increasing?(values),
    do:
      values
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [first, second] -> DateTime.compare(first, second) == :lt end)

  defp utc(value) do
    case DateTime.from_unix(DateTime.to_unix(value, :microsecond), :microsecond) do
      {:ok, %{year: year} = utc} when year in 0..9999 ->
        {:ok, %{utc | microsecond: value.microsecond}}

      _ ->
        invalid(:coordinate_range)
    end
  end

  defp matches?(value, nominal, zone),
    do: datetime?(value) and value.time_zone == zone and DateTime.to_naive(value) == nominal

  defp date?(%Date{calendar: Calendar.ISO, year: year} = value),
    do: year in 0..9999 and Enum.sort(Map.keys(value)) == @date_keys and Temporal.date?(value)

  defp date?(_), do: false

  defp time?(%Time{calendar: Calendar.ISO, microsecond: {0, 0}} = value),
    do: Enum.sort(Map.keys(value)) == @time_keys and Temporal.time?(value)

  defp time?(_), do: false

  defp datetime?(%DateTime{calendar: Calendar.ISO, year: year} = value) do
    year in 0..9999 and Enum.sort(Map.keys(value)) == @datetime_keys and Temporal.datetime?(value) and
      text?(value.time_zone) and metadata_text?(value.zone_abbr) and
      value.utc_offset in -93_599..93_599 and value.std_offset in -93_599..93_599 and
      (value.utc_offset + value.std_offset) in -89_999..93_599
  end

  defp datetime?(_), do: false

  defp weekdays?([], _, count), do: count > 0

  defp weekdays?([day | rest], previous, count) when day in 1..7 and day > previous and count < 7,
    do: weekdays?(rest, day, count + 1)

  defp weekdays?(_, _, _), do: false

  defp text?(text), do: is_binary(text) and byte_size(text) in 1..256 and String.valid?(text)

  defp metadata_text?(text),
    do: is_binary(text) and byte_size(text) <= 256 and String.valid?(text)

  defp database?(%TimeZoneProvider{} = value), do: TimeZoneProvider.valid?(value)

  defp database?(module) when is_atom(module),
    do:
      Code.ensure_loaded?(module) and
        function_exported?(module, :time_zone_periods_from_wall_datetime, 2) and
        function_exported?(module, :time_zone_period_from_utc_iso_days, 2)

  defp database?(_), do: false
  defp require_field(true, _), do: :ok
  defp require_field(false, field), do: invalid(field)
  defp invalid(field), do: {:error, {:invalid, :civil_occurrences, field}}
end
