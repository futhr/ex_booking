defmodule ExBooking.OccurrenceCursor do
  @moduledoc """
  An inert continuation bound to the complete recurrence query.

  Use only the cursor returned by `ExBooking.occurrences/3`. Its position and
  prefix count are revalidated within the caller's work budget. It is not a
  signed token, persistent job or evidence that earlier results were processed.

  ## Example

      iex> {:ok, page} =
      ...>   ExBooking.occurrences("FREQ=DAILY", ~U[2026-07-13 06:00:00Z],
      ...>     from: ~U[2026-07-13 00:00:00Z],
      ...>     until: ~U[2026-07-16 00:00:00Z],
      ...>     time_zone_database: Calendar.UTCOnlyTimeZoneDatabase,
      ...>     time_zone_basis: "utc-v1",
      ...>     limit: 1
      ...>   )
      ...>
      ...> page.next_cursor.emitted_count
      1
  """

  @enforce_keys [:basis, :next_offset_days, :emitted_count]
  defstruct [:basis, :next_offset_days, :emitted_count]

  @typedoc "Complete normalized query basis and verified next candidate."
  @type t :: %__MODULE__{
          basis: map(),
          next_offset_days: non_neg_integer(),
          emitted_count: non_neg_integer()
        }
end
