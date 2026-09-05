defmodule ExBooking.Resource do
  @moduledoc """
  A bookable resource.

  A resource is usually a bookable person, but can also represent a pooled seat.
  Busy intervals, booking reservations, daily booking counts, capacity, and
  fairness counters are explicit inputs maintained by the consuming
  application, which keeps assignment stateless and repeatable.

  ## Example

      iex> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC", capacity: 2}
      ...> {resource.id, resource.capacity}
      {"resource_1", 2}

  """

  alias ExBooking.Interval
  alias ExBooking.Reservation

  @enforce_keys [:id, :timezone]
  defstruct [
    :id,
    :timezone,
    :fairness,
    :meta,
    capacity: 1,
    busy: [],
    reservations: [],
    daily_booking_counts: %{}
  ]

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
          reservations: [Reservation.t()],
          daily_booking_counts: %{optional(Date.t()) => non_neg_integer()},
          fairness: fairness() | nil,
          meta: map() | nil
        }
  @doc """
  Rejects repeated ids in an already validated resource list.

  ## Examples

      iex> resource = %ExBooking.Resource{id: "a", timezone: "Etc/UTC"}
      ...> ExBooking.Resource.validate_ids([resource, resource])
      {:error, {:invalid, :resource_id, {:duplicate, "a"}}}
  """
  @spec validate_ids([t()]) :: :ok | {:error, {:invalid, :resource_id, {:duplicate, String.t()}}}
  def validate_ids(resources) do
    result =
      Enum.reduce_while(resources, MapSet.new(), fn resource, seen ->
        if MapSet.member?(seen, resource.id),
          do: {:halt, {:error, {:invalid, :resource_id, {:duplicate, resource.id}}}},
          else: {:cont, MapSet.put(seen, resource.id)}
      end)

    case result do
      %MapSet{} -> :ok
      error -> error
    end
  end
end
