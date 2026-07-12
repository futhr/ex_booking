defmodule ExBooking.Reservation do
  @moduledoc """
  A booking-specific capacity reservation supplied by the consumer.

  Unlike generic calendar busy intervals, reservations carry the number of
  seats consumed from a resource. The kernel uses this fact for pool
  availability and never derives it from the number of overlapping events.

  ## Example

      iex> interval =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> reservation = %ExBooking.Reservation{interval: interval, capacity_consumed: 2}
      ...> reservation.capacity_consumed
      2

  """

  alias ExBooking.Interval

  @enforce_keys [:interval]
  defstruct [:interval, :meta, capacity_consumed: 1]

  @typedoc "A booking-specific reservation of resource capacity."
  @type t :: %__MODULE__{
          interval: Interval.t(),
          capacity_consumed: pos_integer(),
          meta: map() | nil
        }
end
