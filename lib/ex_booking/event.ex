defmodule ExBooking.Event do
  @moduledoc """
  Canonical booking events — the cross-system contract consumed by
  orchestration, analytics, and billing layers.

  The kernel emits events inside `ExBooking.Decision.t()`; the consumer
  stamps `occurred_at`, assigns ids, and publishes. `routing_context` is the
  untouched `ExBooking.Request.t()` context, which is how UTM/CRM
  attribution reaches downstream systems without kernel involvement.
  See `docs/specs/SP.05-lifecycle-and-events.md`.
  """

  alias ExBooking.Interval

  @enforce_keys [:type]
  defstruct [
    :type,
    :slot,
    :meeting_type_id,
    resource_ids: [],
    routing_context: %{},
    data: %{}
  ]

  @typedoc "Canonical event name."
  @type type ::
          :booking_reserved
          | :booking_confirmed
          | :booking_rescheduled
          | :booking_canceled
          | :booking_expired
          | :booking_no_show

  @typedoc "A canonical booking event."
  @type t :: %__MODULE__{
          type: type(),
          slot: Interval.t() | nil,
          resource_ids: [String.t()],
          meeting_type_id: String.t() | nil,
          routing_context: map(),
          data: map()
        }
end
