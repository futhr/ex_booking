defmodule ExBooking.Decision do
  @moduledoc """
  The result of a booking decision.

  A decision is returned for both accepted and rejected booking attempts. For
  rejections, `reasons` explain what failed and `alternatives` can be shown to
  the invitee. For accepted transitions, `events` and `intents` tell the
  consumer application what to persist, publish, or execute.

  ## Example

      iex> decision = %ExBooking.Decision{status: :ok, resource_ids: ["resource_1"]}
      ...> {decision.status, decision.resource_ids}
      {:ok, ["resource_1"]}

  """

  alias ExBooking.Event
  alias ExBooking.Hold
  alias ExBooking.Interval

  @enforce_keys [:status]
  defstruct [
    :status,
    :slot,
    :meeting_type_id,
    resource_ids: [],
    seat_allocations: [],
    alternatives: [],
    reasons: [],
    events: [],
    intents: []
  ]

  @typedoc "Decision outcome."
  @type status :: :ok | :conflict | :policy_reject | :needs_routing

  @typedoc "Machine-readable rejection reason."
  @type reason :: tuple() | atom()

  @typedoc "A side effect for the consumer to execute, in order."
  @type intent ::
          {:reserve, Hold.t()}
          | {:release, String.t()}
          | {:calendar_event, :create | :cancel | :move, map()}
          | {:notify, atom(), map()}
          | {:emit, Event.t()}

  @typedoc "A booking decision."
  @type t :: %__MODULE__{
          status: status(),
          slot: Interval.t() | nil,
          meeting_type_id: String.t() | nil,
          resource_ids: [String.t()],
          seat_allocations: [
            %{resource_id: String.t(), capacity_consumed: pos_integer()}
          ],
          alternatives: [Interval.t()],
          reasons: [reason()],
          events: [Event.t()],
          intents: [intent()]
        }
end
