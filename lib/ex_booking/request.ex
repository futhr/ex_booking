defmodule ExBooking.Request do
  @moduledoc """
  An invitee's booking request.

  A request carries the desired meeting type, invitee timezone, requested slot,
  preferred resources, metadata, and opaque routing context. Routing context is
  passed through to scoring and events without the kernel interpreting it.

  ## Example

      iex> request = %ExBooking.Request{
      ...>   meeting_type_id: "intro",
      ...>   invitee_timezone: "America/New_York",
      ...>   routing_context: %{source: "website"}
      ...> }
      ...>
      ...> request.routing_context.source
      "website"

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
