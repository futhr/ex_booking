defmodule ExBooking.Occurrence do
  @moduledoc """
  An original calendar occurrence, without duration or execution authority.

  `nominal` preserves local wall time; `starts_at` is the resolved UTC instant.
  `ordinal` counts valid occurrences from DTSTART, including those before the
  query horizon. Nonexistent wall times consume no ordinal. `resolution`
  records unique or first/second-fold resolution.

  ## Example

      iex> occurrence = %ExBooking.Occurrence{
      ...>   nominal: ~N[2026-07-13 06:00:00],
      ...>   starts_at: ~U[2026-07-13 06:00:00Z],
      ...>   ordinal: 1,
      ...>   resolution: :unique
      ...> }
      ...>
      ...> occurrence.ordinal
      1
  """

  @enforce_keys [:nominal, :starts_at, :ordinal, :resolution]
  defstruct [:nominal, :starts_at, :ordinal, :resolution]

  @typedoc "Original recurrence coordinate and resolution."
  @type t :: %__MODULE__{
          nominal: NaiveDateTime.t(),
          starts_at: DateTime.t(),
          ordinal: pos_integer(),
          resolution: :unique | :first_fold | :second_fold
        }
end
