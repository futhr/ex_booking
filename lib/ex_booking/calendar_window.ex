defmodule ExBooking.CalendarWindow do
  @moduledoc """
  Bounded inclusive selection of explicit dates, preserving consumer order.

  This operation needs no timezone database or clock. A calendar day is not
  converted into an instant; optional instants do not change date selection.
  """

  alias ExBooking.DatedOccurrence
  alias ExBooking.Temporal

  @doc """
  Selects supplied occurrences in the inclusive `from`/`to` date window.

  Options are `:input_limit` (default 10000) and `:limit` (default 1000), each
  an integer from 1 through 100000. All entries within the input bound are
  validated, including dates outside the window. Excess input or output returns
  a closed error without partial results. Unknown or duplicate options reject.

  ## Example

      iex> entry = %ExBooking.DatedOccurrence{on: ~D[2026-10-14], reference: "one"}
      ...> ExBooking.CalendarWindow.select([entry], ~D[2026-10-14], ~D[2026-10-14])
      {:ok, [entry]}
  """
  @spec select([DatedOccurrence.t()], Date.t(), Date.t(), keyword()) ::
          {:ok, [DatedOccurrence.t()]} | {:error, term()}
  def select(occurrences, from, to, opts \\ []) do
    with {:ok, limits} <- limits(opts),
         :ok <- range(from, to) do
      select_entries(occurrences, {from, to}, limits, {0, 0}, [])
    end
  end

  defp limits(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:input_limit, :limit])) and
         length(opts) == length(Enum.uniq(Keyword.keys(opts))) do
      input = Keyword.get(opts, :input_limit, 10_000)
      output = Keyword.get(opts, :limit, 1000)

      if is_integer(input) and input in 1..100_000 and is_integer(output) and
           output in 1..100_000,
         do: {:ok, {input, output}},
         else: invalid(:options)
    else
      invalid(:options)
    end
  end

  defp limits(_), do: invalid(:options)

  defp range(from, to) do
    if date?(from) and date?(to) and Date.compare(from, to) != :gt,
      do: :ok,
      else: invalid(:range)
  end

  defp select_entries([], _, _, _, selected), do: {:ok, Enum.reverse(selected)}

  defp select_entries([_ | _], _, {input, _}, {count, _}, _) when count >= input,
    do: {:error, {:limit, :date_window, :input}}

  defp select_entries([entry | rest], {from, to} = range, limits, {count, matched}, selected) do
    with :ok <- validate(entry) do
      if Date.compare(entry.on, from) != :lt and Date.compare(entry.on, to) != :gt do
        select_match(entry, {rest, range}, limits, {count + 1, matched}, selected)
      else
        select_entries(rest, range, limits, {count + 1, matched}, selected)
      end
    end
  end

  defp select_entries(_, _, _, _, _), do: invalid(:occurrences)

  defp select_match(_, _, {_, output}, {_, matched}, _) when matched >= output,
    do: {:error, {:limit, :date_window, :output}}

  defp select_match(entry, {rest, range}, limits, {count, matched}, selected),
    do: select_entries(rest, range, limits, {count, matched + 1}, [entry | selected])

  defp validate(%DatedOccurrence{on: on, starts_at: starts_at, reference: reference} = entry)
       when map_size(entry) == 4 do
    if date?(on) and instant?(starts_at) and reference?(reference),
      do: :ok,
      else: invalid(:occurrence)
  end

  defp validate(_), do: invalid(:occurrence)

  defp date?(%Date{calendar: Calendar.ISO, year: year} = date)
       when year in 0..9999 and map_size(date) == 5,
       do: Temporal.date?(date)

  defp date?(_), do: false

  defp instant?(nil), do: true

  defp instant?(
         %DateTime{
           calendar: Calendar.ISO,
           year: year,
           time_zone: "Etc/UTC",
           zone_abbr: "UTC",
           utc_offset: 0,
           std_offset: 0
         } = instant
       )
       when year in 0..9999 and map_size(instant) == 13,
       do: Temporal.datetime?(instant)

  defp instant?(_), do: false

  defp reference?(nil), do: true

  defp reference?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: String.valid?(value)

  defp reference?(_), do: false

  defp invalid(reason), do: {:error, {:invalid, :date_window, reason}}
end
