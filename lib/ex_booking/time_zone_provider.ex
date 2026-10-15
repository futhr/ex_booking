defmodule ExBooking.TimeZoneProvider do
  @moduledoc """
  An explicit immutable timezone context for recurrence and civil queries.

  Implement `c:resolve/3` and `c:localize/3`, then pass that existing module and
  at most 1 MiB of binary context to `new/2`. The context supplies immutable data;
  no registry, process, I/O or ambient database is selected. Construction checks
  the required exports and native provider shape, not the correctness or
  immutability of callback code/data. Consumers own those obligations and each
  callback's work/runtime.

  The required resolver returns `{:ok, datetime}`,
  `{:ambiguous, first, second}`, `:gap` or `{:error, reason}`. Localization returns
  `{:ok, local}` or `{:error, reason}`, preserving the original instant and its
  precision. `from_naive/3` and `shift_zone/3` validate their respective results
  with offset components and totals in `-86_400..86_400` seconds. Explicit
  `Calendar.TimeZoneDatabase` modules remain supported by these helpers.

  For civil queries, a module may additionally implement `c:resolve_civil/3`.
  It accepts the same inputs and legacy result shapes, plus
  `{:ambiguous, candidates}`: the complete proper list of 2–732 native local
  DateTimes, strictly ordered by UTC. Return every alternative without truncating
  intermediate candidates. `ExBooking.CivilRecurrence.occurrences/3` prefers
  this optional callback when exported and never falls back after its refusal,
  malformed result or implementation fault. If absent, it calls `c:resolve/3`.
  Civil queries validate every alternative under their own offset/work profile.

  The optional callback does not change provider constructor requirements or
  legacy operations: `from_naive/3` and original RRULE enumeration through
  `ExBooking.occurrences/3` still use only `c:resolve/3`; `shift_zone/3` still uses
  `c:localize/3`. Their accepted shapes and offset bounds are unchanged.
  Original recurrence cursors retain the complete native provider/context;
  civil queries have no cursor. A retained context is data attribution, not
  authorization or proof of installed timezone authenticity.
  """

  alias ExBooking.Temporal

  @enforce_keys [:module, :context]
  defstruct [:module, :context]

  @type t :: %__MODULE__{module: module(), context: binary()}
  @type database :: module() | t()
  @type resolution ::
          {:ok, DateTime.t()}
          | {:ambiguous, DateTime.t(), DateTime.t()}
          | :gap
          | {:error, term()}

  @callback resolve(NaiveDateTime.t(), String.t(), binary()) :: resolution()
  @callback localize(DateTime.t(), String.t(), binary()) ::
              {:ok, DateTime.t()} | {:error, term()}

  @typedoc "Civil-only resolution, optionally retaining a complete bounded ambiguity list."
  @type civil_resolution :: resolution() | {:ambiguous, [DateTime.t()]}

  @doc """
  Optionally resolves every civil alternative, in strictly increasing UTC order.

  Only civil queries select this callback. An ambiguity list has 2–732 native
  DateTimes and is completely validated before policy/filtering. Refusals and
  faults never fall back to `c:resolve/3`. Original RRULE enumeration and
  `from_naive/3` continue to use `c:resolve/3` only; `shift_zone/3` retains its
  existing `c:localize/3` path.
  """
  @callback resolve_civil(NaiveDateTime.t(), String.t(), binary()) :: civil_resolution()
  @optional_callbacks resolve_civil: 3

  @doc """
  Constructs a provider for an existing module and at most 1 MiB of context.

  ## Example

      iex> ExBooking.TimeZoneProvider.new(String, <<>>)
      {:error, :invalid_time_zone_provider}
  """
  @spec new(term(), term()) :: {:ok, t()} | {:error, :invalid_time_zone_provider}
  def new(module, context) do
    provider = %__MODULE__{module: module, context: context}
    if valid?(provider), do: {:ok, provider}, else: {:error, :invalid_time_zone_provider}
  end

  @doc """
  Rechecks the complete native value and both installed callback seams.

  ## Example

      iex> ExBooking.TimeZoneProvider.valid?(nil)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{module: module, context: context} = value) when map_size(value) == 3 do
    is_binary(context) and byte_size(context) <= 1_048_576 and is_atom(module) and
      Code.ensure_loaded?(module) and function_exported?(module, :resolve, 3) and
      function_exported?(module, :localize, 3)
  end

  def valid?(_), do: false

  @doc """
  Resolves an ISO local label through an explicit provider or Calendar database.

  Provider gap output is `:gap`; Calendar module gaps retain their native tuple.
  Malformed provider outputs refuse; callback error payloads become the fixed
  `:time_zone_provider_refused` code. Callback implementation faults propagate.

  ## Example

      iex> ExBooking.TimeZoneProvider.from_naive(
      ...>   ~N[2026-07-13 06:00:00],
      ...>   "Etc/UTC",
      ...>   Calendar.UTCOnlyTimeZoneDatabase
      ...> )
      {:ok, ~U[2026-07-13 06:00:00Z]}
  """
  @spec from_naive(NaiveDateTime.t(), String.t(), database()) ::
          resolution() | {:gap, DateTime.t(), DateTime.t()}
  def from_naive(nominal, zone, %__MODULE__{} = provider) do
    if valid?(provider) and nominal?(nominal) and zone?(zone) do
      provider.module.resolve(nominal, zone, provider.context)
      |> resolution(nominal, zone)
    else
      {:error, :invalid_time_zone_provider}
    end
  end

  def from_naive(nominal, zone, database) when is_atom(database),
    do:
      if(module_database?(database),
        do: DateTime.from_naive(nominal, zone, database),
        else: {:error, :invalid_time_zone_provider}
      )

  def from_naive(_, _, _), do: {:error, :invalid_time_zone_provider}

  @doc """
  Localizes an instant through an explicit provider or Calendar database.

  Provider success must preserve the complete instant and its precision.
  Callback error payloads become `:time_zone_provider_refused`, without context.

  ## Example

      iex> ExBooking.TimeZoneProvider.shift_zone(
      ...>   ~U[2026-07-13 06:00:00Z],
      ...>   "Etc/UTC",
      ...>   Calendar.UTCOnlyTimeZoneDatabase
      ...> )
      {:ok, ~U[2026-07-13 06:00:00Z]}
  """
  @spec shift_zone(DateTime.t(), String.t(), database()) :: {:ok, DateTime.t()} | {:error, term()}
  def shift_zone(datetime, zone, %__MODULE__{} = provider) do
    if valid?(provider) and datetime?(datetime) and zone?(zone) do
      provider.module.localize(datetime, zone, provider.context)
      |> localization(datetime, zone)
    else
      {:error, :invalid_time_zone_provider}
    end
  end

  def shift_zone(datetime, zone, database) when is_atom(database),
    do:
      if(module_database?(database),
        do: DateTime.shift_zone(datetime, zone, database),
        else: {:error, :invalid_time_zone_provider}
      )

  def shift_zone(_, _, _), do: {:error, :invalid_time_zone_provider}

  defp resolution({:ok, datetime}, nominal, zone) do
    if matches?(datetime, nominal, zone), do: {:ok, datetime}, else: invalid_result()
  end

  defp resolution({:ambiguous, first, second}, nominal, zone) do
    if matches?(first, nominal, zone) and matches?(second, nominal, zone) and
         DateTime.compare(first, second) == :lt,
       do: {:ambiguous, first, second},
       else: invalid_result()
  end

  defp resolution(:gap, _, _), do: :gap
  defp resolution({:error, _}, _, _), do: {:error, :time_zone_provider_refused}
  defp resolution(_, _, _), do: invalid_result()

  defp localization({:ok, local}, datetime, zone) do
    if datetime?(local) and local.time_zone == zone and
         local.microsecond == datetime.microsecond and DateTime.compare(local, datetime) == :eq,
       do: {:ok, local},
       else: invalid_result()
  end

  defp localization({:error, _}, _, _), do: {:error, :time_zone_provider_refused}
  defp localization(_, _, _), do: invalid_result()

  defp matches?(datetime, nominal, zone),
    do:
      datetime?(datetime) and datetime.time_zone == zone and
        DateTime.to_naive(datetime) == nominal

  defp datetime?(%DateTime{calendar: Calendar.ISO, year: year} = value),
    do:
      Temporal.datetime?(value) and year in 0..9999 and
        abs(value.utc_offset) <= 86_400 and abs(value.std_offset) <= 86_400 and
        abs(value.utc_offset + value.std_offset) <= 86_400

  defp datetime?(_), do: false

  defp nominal?(%NaiveDateTime{calendar: Calendar.ISO, year: year} = value),
    do:
      year in 0..9999 and Temporal.date?(NaiveDateTime.to_date(value)) and
        Temporal.time?(NaiveDateTime.to_time(value))

  defp nominal?(_), do: false
  defp zone?(zone), do: is_binary(zone) and byte_size(zone) in 1..256 and String.valid?(zone)

  defp module_database?(module),
    do:
      Code.ensure_loaded?(module) and
        function_exported?(module, :time_zone_periods_from_wall_datetime, 2) and
        function_exported?(module, :time_zone_period_from_utc_iso_days, 2)

  defp invalid_result, do: {:error, :invalid_time_zone_result}
end
