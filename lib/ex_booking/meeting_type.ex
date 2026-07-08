defmodule ExBooking.MeetingType do
  @moduledoc """
  A bookable meeting template.

  A meeting type defines duration, slot grid, participant mode, capacity, and
  lifecycle policies. `slot_interval_min` is deliberately independent from
  `duration_min`, so a 30-minute meeting can be offered every 15 minutes.

  ## Example

      iex> meeting_type = %ExBooking.MeetingType{
      ...>   id: "intro",
      ...>   duration_min: 30,
      ...>   slot_interval_min: 15
      ...> }
      ...>
      ...> {meeting_type.duration_min, meeting_type.slot_interval_min}
      {30, 15}

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

  @typedoc "Which resources must be free for a slot."
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
