defmodule ExBooking.Decision do
  @moduledoc """
  The kernel's answer to `ExBooking.decide/5` and `ExBooking.reschedule/6`.

  A decision is returned even for rejections (`status: :conflict` or
  `:policy_reject`) so consumers can present `alternatives` and
  machine-readable `reasons`. `intents` describe the side effects the
  consumer must execute; the kernel performs none of them.
  """

  alias ExBooking.Event
  alias ExBooking.Hold
  alias ExBooking.Interval

  @enforce_keys [:status]
  defstruct [
    :status,
    :slot,
    resource_ids: [],
    alternatives: [],
    reasons: [],
    events: [],
    intents: []
  ]

  @typedoc "Decision outcome."
  @type status :: :ok | :conflict | :policy_reject | :needs_routing

  @typedoc "Machine-readable rejection reason (see spec 02 error vocabulary)."
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
          resource_ids: [String.t()],
          alternatives: [Interval.t()],
          reasons: [reason()],
          events: [Event.t()],
          intents: [intent()]
        }
end
