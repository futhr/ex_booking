defmodule ExBooking.Hold do
  @moduledoc """
  A temporary reservation as pure data.

  Consumers persist holds, include them as `kind: :hold` busy time in
  subsequent availability searches, and expire them by comparing
  `expires_at` with their own clock. The kernel never expires anything —
  it does not read the clock. Hold ids are consumer-supplied so consumers
  can use them as idempotency keys.
  """

  alias ExBooking.Interval

  @enforce_keys [:id, :slot, :resource_ids, :meeting_type_id, :expires_at]
  defstruct [:id, :slot, :resource_ids, :meeting_type_id, :expires_at]

  @typedoc "A hold on a slot."
  @type t :: %__MODULE__{
          id: String.t(),
          slot: Interval.t(),
          resource_ids: [String.t()],
          meeting_type_id: String.t(),
          expires_at: DateTime.t()
        }
end
