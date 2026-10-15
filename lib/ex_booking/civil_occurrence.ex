defmodule ExBooking.CivilOccurrence do
  @moduledoc """
  An original local label paired with one UTC instant from a civil query.

  `ExBooking.CivilRecurrence.occurrences/3` and `ExBooking.civil_occurrences/3`
  return these native points with three fields:

    * `:nominal` is the selected ISO `NaiveDateTime`, retaining its original local
      date/time label.
    * `:starts_at` is the corresponding original UTC `DateTime`, never clipped to
      a query boundary.
    * `:resolution` is `:unique`, `:first_fold`, `:second_fold` or `{:fold, index}`
      for local positions 3–732. Fold points share one nominal label with distinct,
      ordered UTC instants. A fold position is not a recurrence ordinal.

  A fold position belongs to the complete UTC-ordered resolution of one local
  label, before policy and UTC filtering. If earlier alternatives fall outside
  the query, a retained `{:fold, 3}` stays position 3; it is not renumbered.

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
          resolution: :unique | :first_fold | :second_fold | {:fold, 3..732}
        }
end
