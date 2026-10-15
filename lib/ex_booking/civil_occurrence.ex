defmodule ExBooking.CivilOccurrence do
  @moduledoc """
  An original local label paired with one UTC instant from a civil query.

  `ExBooking.CivilRecurrence.occurrences/3` and `ExBooking.civil_occurrences/3`
  return these native points with three fields:

    * `:nominal` is the selected ISO `NaiveDateTime`, retaining its original local
      date/time label.
    * `:starts_at` is the corresponding original UTC `DateTime`, never clipped to
      a query boundary.
    * `:resolution` is `:unique`, `:first_fold` or `:second_fold`. With both folds,
      two points share a nominal label but have different, ordered UTC instants.

  A point has no duration, end, identifier or cursor. Unlike
  `ExBooking.Occurrence`, it has no ordinal counted from DTSTART. The caller owns
  identity and deduplication across queries; these values alone establish neither
  booking availability nor permission to execute an effect.

  ## Examples

      iex> point = %ExBooking.CivilOccurrence{
      ...>   nominal: ~N[2026-07-13 09:00:00],
      ...>   starts_at: ~U[2026-07-13 09:00:00Z],
      ...>   resolution: :unique
      ...> }
      ...>
      ...> point.resolution
      :unique
  """

  @enforce_keys [:nominal, :starts_at, :resolution]
  defstruct [:nominal, :starts_at, :resolution]

  @typedoc "A query point, without a global recurrence ordinal or execution authority."
  @type t :: %__MODULE__{
          nominal: NaiveDateTime.t(),
          starts_at: DateTime.t(),
          resolution: :unique | :first_fold | :second_fold
        }
end
