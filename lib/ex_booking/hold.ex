defmodule ExBooking.Hold do
  @moduledoc """
  Temporary reservation data.

  Holds are caller-owned records. The kernel can emit a reserve intent, treat
  holds as busy intervals on later searches, and compute a release transition;
  it never stores, expires, or refreshes them itself.

  ## Example

      iex> slot = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> hold = %ExBooking.Hold{
      ...>   id: "hold_1",
      ...>   slot: slot,
      ...>   resource_ids: ["resource_1"],
      ...>   meeting_type_id: "intro",
      ...>   expires_at: ~U[2026-07-13 08:45:00Z]
      ...> }
      ...>
      ...> hold.id
      "hold_1"

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
