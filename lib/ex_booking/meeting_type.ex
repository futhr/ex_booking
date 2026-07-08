defmodule ExBooking.MeetingType do
  @moduledoc """
  A bookable meeting template: duration, slot grid, buffers, capacity, and
  cancellation/reschedule policies.

  `slot_interval_min` is deliberately independent of `duration_min` — a
  30-minute meeting can sit on a 15-minute grid. `nil` falls back to
  `duration_min`.
  """

  alias ExBooking.AvailabilityRule

  @enforce_keys [:id, :duration_min]
  defstruct [
    :id,
    :duration_min,
    :slot_interval_min,
    :buffers,
    :cancellation_policy,
    :reschedule_policy,
    :meta,
    capacity_required: 1,
    participants: :one
  ]

  @typedoc "Cancellation or reschedule policy."
  @type policy :: %{min_notice_min: non_neg_integer(), allowed: boolean()}

  @typedoc "Which resources must be free for a slot (see spec 03 §5)."
  @type participants :: :one | :collective | :pool

  @typedoc "A meeting type."
  @type t :: %__MODULE__{
          id: String.t(),
          duration_min: pos_integer(),
          slot_interval_min: pos_integer() | nil,
          buffers: AvailabilityRule.buffers() | nil,
          capacity_required: pos_integer(),
          participants: participants(),
          cancellation_policy: policy() | nil,
          reschedule_policy: policy() | nil,
          meta: map() | nil
        }
end
