defmodule ExBooking.AvailabilityRule do
  @moduledoc """
  Offerable-time and policy input for one resource.

  An availability rule describes weekly wall-time windows in a named timezone,
  optional date overrides, absolute blackout intervals, and policy constraints
  such as lead time or daily caps. Expansion turns this data into UTC
  intervals before busy time is subtracted.

  ## Example

      iex> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Europe/Stockholm",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}],
      ...>   lead_time_min: 60
      ...> }
      ...>
      ...> {rule.timezone, rule.lead_time_min}
      {"Europe/Stockholm", 60}

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
  in the rule timezone.
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
