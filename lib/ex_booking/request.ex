defmodule ExBooking.Request do
  @moduledoc """
  An invitee's booking intent, before decision.

  `routing_context` is opaque: the kernel never interprets it. It is surfaced
  to the assignment scoring hook and round-tripped into events untouched —
  this is how CRM/GTM attribution flows through without the kernel learning
  CRM semantics.
  """

  alias ExBooking.Interval

  @enforce_keys [:meeting_type_id, :invitee_timezone]
  defstruct [
    :meeting_type_id,
    :invitee_timezone,
    :slot,
    :metadata,
    preferred_resource_ids: [],
    routing_context: %{}
  ]

  @typedoc "A booking request."
  @type t :: %__MODULE__{
          meeting_type_id: String.t(),
          invitee_timezone: String.t(),
          slot: Interval.t() | nil,
          preferred_resource_ids: [String.t()],
          routing_context: map(),
          metadata: map() | nil
        }
end
