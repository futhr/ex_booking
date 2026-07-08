defmodule ExBooking.Resource do
  @moduledoc """
  A bookable resource.

  A resource is usually a host, but can also represent a pooled seat. Busy
  intervals, capacity, and fairness counters are explicit inputs maintained by
  the consuming application, which keeps assignment stateless and repeatable.

  ## Example

      iex> resource = %ExBooking.Resource{id: "host_1", timezone: "Etc/UTC", capacity: 2}
      ...> {resource.id, resource.capacity}
      {"host_1", 2}

  """

  alias ExBooking.Interval

  @enforce_keys [:id, :timezone]
  defstruct [:id, :timezone, :fairness, :meta, capacity: 1, busy: []]

  @typedoc "Explicit fairness inputs for assignment strategies."
  @type fairness :: %{
          assignments_count: non_neg_integer(),
          last_assigned_at: DateTime.t() | nil,
          weight: number(),
          priority: integer()
        }

  @typedoc "A bookable resource."
  @type t :: %__MODULE__{
          id: String.t(),
          timezone: String.t(),
          capacity: pos_integer(),
          busy: [Interval.t()],
          fairness: fairness() | nil,
          meta: map() | nil
        }
end
