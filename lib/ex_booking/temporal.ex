defmodule ExBooking.Temporal do
  @moduledoc "Field validation for caller-built calendar values before temporal arithmetic."

  @doc """
  Checks a date's fields using its calendar.

  ## Examples

      iex> ExBooking.Temporal.date?(~D[2026-07-13])
      true
  """
  @spec date?(term()) :: boolean()
  def date?(%Date{} = date), do: date_fields?(date)
  def date?(_), do: false

  @doc """
  Checks a time's fields and microsecond representation using its calendar.

  ## Examples

      iex> ExBooking.Temporal.time?(~T[09:00:00.123456])
      true
  """
  @spec time?(term()) :: boolean()
  def time?(%Time{} = time), do: time_fields?(time)
  def time?(_), do: false

  @doc """
  Checks datetime fields before comparison or conversion.

  Zone names and offsets must have their native types. This is structural
  validation, not verification of supplied offsets against timezone history.
  Calendar callback implementation errors are allowed to propagate.

  ## Examples

      iex> ExBooking.Temporal.datetime?(~U[2026-07-13 09:00:00Z])
      true
  """
  @spec datetime?(term()) :: boolean()
  def datetime?(
        %DateTime{
          utc_offset: utc_offset,
          std_offset: std_offset,
          time_zone: time_zone,
          zone_abbr: zone_abbr
        } = datetime
      )
      when is_integer(utc_offset) and is_integer(std_offset) and is_binary(time_zone) and
             time_zone != "" and is_binary(zone_abbr) do
    date_fields?(datetime) and time_fields?(datetime)
  end

  def datetime?(_), do: false

  defp date_fields?(%{year: year, month: month, day: day, calendar: calendar})
       when is_integer(year) and is_integer(month) and is_integer(day) and is_atom(calendar) do
    function_exported?(calendar, :valid_date?, 3) and calendar.valid_date?(year, month, day)
  end

  defp date_fields?(_), do: false

  defp time_fields?(%{
         hour: hour,
         minute: minute,
         second: second,
         microsecond: {value, precision} = microsecond,
         calendar: calendar
       })
       when is_integer(hour) and is_integer(minute) and is_integer(second) and
              is_integer(value) and value in 0..999_999 and
              is_integer(precision) and precision in 0..6 and is_atom(calendar) do
    function_exported?(calendar, :valid_time?, 4) and
      calendar.valid_time?(hour, minute, second, microsecond)
  end

  defp time_fields?(_), do: false
end
