defmodule ExBooking.Resource do
  @moduledoc """
  A bookable person or pooled seat.

  Fairness counters are explicit inputs maintained by the consumer — the
  kernel never derives them from history, which keeps assignment stateless
  and deterministic (`docs/specs/SP.04-assignment.md`).
  """

  alias ExBooking.Interval

  @enforce_keys [:id, :timezone]
  defstruct [:id, :timezone, :fairness, :meta, capacity: 1, busy: []]

  @typedoc "Explicit fairness inputs for assignment strategies."
  @type fairness :: %{
          assignments_count: non_neg_integer(),
          last_assigned_at: DateTime.t() | nil,
          weight: number(),
          priority: integer()
        }

  @typedoc "A bookable resource."
  @type t :: %__MODULE__{
          id: String.t(),
          timezone: String.t(),
          capacity: pos_integer(),
          busy: [Interval.t()],
          fairness: fairness() | nil,
          meta: map() | nil
        }
end
