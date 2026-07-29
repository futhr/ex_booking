defmodule ExBooking.Event do
  @moduledoc """
  Canonical booking events emitted by decisions.

  Events describe what happened in booking-domain language: confirmed,
  reserved, rescheduled, canceled, expired, or marked no-show. The consumer
  stamps ids and occurrence times, stores the events, and publishes them to
  analytics, billing, calendar, or notification systems as needed.

  ## Example

      iex> event = %ExBooking.Event{type: :booking_confirmed, resource_ids: ["resource_1"]}
      ...> event.type
      :booking_confirmed

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
