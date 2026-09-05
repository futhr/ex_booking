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
          optional(:assignments_count) => non_neg_integer(),
          optional(:last_assigned_at) => DateTime.t() | nil,
          optional(:weight) => number(),
          optional(:priority) => integer()
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

  @fairness_fields [:assignments_count, :last_assigned_at, :weight, :priority]

  @doc """
  Validates optional fairness fields without interpreting an assignment strategy.

  ## Examples

      iex> ExBooking.Resource.validate_fairness("a", %{assignments_count: 0})
      :ok
      iex> ExBooking.Resource.validate_fairness("a", %{weight: 0})
      {:error, {:invalid, :resource_fairness, {"a", {:weight, 0}}}}
  """
  @spec validate_fairness(String.t(), term()) ::
          :ok | {:error, {:invalid, :resource_fairness, {String.t(), term()}}}
  def validate_fairness(_, nil), do: :ok

  def validate_fairness(id, fairness) when is_map(fairness) and not is_struct(fairness) do
    invalid = Enum.find(fairness, &invalid_fairness?/1)

    if invalid,
      do: {:error, {:invalid, :resource_fairness, {id, invalid}}},
      else: :ok
  end

  def validate_fairness(id, fairness),
    do: {:error, {:invalid, :resource_fairness, {id, fairness}}}

  defp invalid_fairness?({key, _}) when key not in @fairness_fields, do: true
  defp invalid_fairness?({:assignments_count, value}), do: not is_integer(value) or value < 0

  defp invalid_fairness?({:last_assigned_at, value}),
    do: value != nil and not is_struct(value, DateTime)

  defp invalid_fairness?({:weight, value}), do: not is_number(value) or value <= 0
  defp invalid_fairness?({:priority, value}), do: not is_integer(value)
end
