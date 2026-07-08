defmodule ExBooking.AvailabilityRule do
  @moduledoc """
  When a resource is *offerable*, before busy subtraction: weekly wall-time
  windows, date overrides, blackouts, and booking policy inputs.

  Windows and overrides are wall time in `timezone`; expansion to concrete
  intervals follows the DST rules in `docs/specs/SP.03-algorithms.md` §2.
  """

  alias ExBooking.Interval

  @enforce_keys [:timezone, :windows]
  defstruct [
    :timezone,
    :windows,
    :booking_window_days,
    :max_per_day,
    overrides: [],
    blackouts: [],
    lead_time_min: 0,
    buffers: %{before_min: 0, after_min: 0}
  ]

  @typedoc """
  A weekly wall-time window. ISO weekday, Monday = 1. An `end_time <=
  start_time` expresses a window crossing midnight into the next day
  (spec 03 §2).
  """
  @type window :: %{weekday: 1..7, start_time: Time.t(), end_time: Time.t()}

  @typedoc "Replacement windows for one date; `windows: []` removes the day."
  @type override :: %{date: Date.t(), windows: [%{start_time: Time.t(), end_time: Time.t()}]}

  @typedoc "Buffer minutes applied around busy time."
  @type buffers :: %{before_min: non_neg_integer(), after_min: non_neg_integer()}

  @typedoc "Availability rule for a resource."
  @type t :: %__MODULE__{
          timezone: String.t(),
          windows: [window()],
          overrides: [override()],
          blackouts: [Interval.t()],
          lead_time_min: non_neg_integer(),
          booking_window_days: pos_integer() | nil,
          buffers: buffers(),
          max_per_day: pos_integer() | nil
        }
end
