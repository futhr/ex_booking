defmodule ExBooking.Policy do
  @moduledoc """
  Pure booking-policy predicates.

  Policy checks evaluate a candidate slot against caller-supplied rules:
  lead time, booking window, and daily cap. Notice policies for cancellation
  and reschedule transitions are evaluated by the facade lifecycle functions.

  ## Example

      iex> rule = %ExBooking.AvailabilityRule{timezone: "Etc/UTC", windows: [], lead_time_min: 60}
      ...> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}
      ...> slot = ExBooking.Interval.new!(~U[2026-07-13 09:30:00Z], ~U[2026-07-13 10:00:00Z])
      ...> ExBooking.Policy.violations(slot, rule, resource, ~U[2026-07-13 09:00:00Z])
      [{:lead_time, 30}]

  """

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.Resource

  @typedoc "A policy violation reason."
  @type reason ::
          {:lead_time, pos_integer()}
          | {:outside_window, Date.t()}
          | {:daily_cap, String.t(), Date.t()}

  @doc """
  Validates a lifecycle notice policy before temporal arithmetic.

  `nil` is an allowed inherited policy. Non-nil policies must contain exactly
  `:allowed` and `:min_notice_min` with their documented types.

  ## Examples

      iex> ExBooking.Policy.validate(%{allowed: true, min_notice_min: 60}, :cancellation_policy)
      :ok

  """
  @spec validate(map() | nil, atom()) :: :ok | {:error, {:invalid, atom(), term()}}
  def validate(nil, _), do: :ok

  def validate(policy, field) when is_map(policy) do
    if Map.keys(policy) |> Enum.sort() == [:allowed, :min_notice_min] and
         is_boolean(policy.allowed) and is_integer(policy.min_notice_min) and
         policy.min_notice_min >= 0 do
      :ok
    else
      {:error, {:invalid, field, policy}}
    end
  end

  def validate(policy, field), do: {:error, {:invalid, field, policy}}

  @doc """
  Returns every policy violation for `slot` against a resource's rule, evaluated
  relative to the caller-supplied `now`. An empty list means the slot is
  allowed.

  ## Examples

      iex> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [],
      ...>   lead_time_min: 120
      ...> }
      ...>
      ...> resource = %ExBooking.Resource{id: "res_1", timezone: "Etc/UTC"}
      ...> slot = ExBooking.Interval.new!(~U[2026-07-13 09:30:00Z], ~U[2026-07-13 10:00:00Z])
      ...> ExBooking.Policy.violations(slot, rule, resource, ~U[2026-07-13 09:00:00Z])
      [{:lead_time, 90}]

  """
  @spec violations(Interval.t(), AvailabilityRule.t(), Resource.t(), DateTime.t()) :: [reason()]
  def violations(
        %Interval{} = slot,
        %AvailabilityRule{} = rule,
        %Resource{} = resource,
        %DateTime{} = now
      ) do
    [
      lead_time_violation(slot, rule, now),
      booking_window_violation(slot, rule, now),
      daily_cap_violation(slot, rule, resource)
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Evaluates a cancellation or reschedule policy against `now` and the existing
  booking. Returns `:ok`, or `{:error, :not_allowed}` when the policy forbids
  the action, or `{:error, :min_notice}` when it is requested too close to the
  start.

  ## Examples

      iex> existing = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> ExBooking.Policy.notice_ok(
      ...>   existing,
      ...>   %{min_notice_min: 60, allowed: true},
      ...>   ~U[2026-07-13 07:00:00Z]
      ...> )
      :ok

      iex> existing = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> ExBooking.Policy.notice_ok(
      ...>   existing,
      ...>   %{min_notice_min: 120, allowed: true},
      ...>   ~U[2026-07-13 08:00:00Z]
      ...> )
      {:error, :min_notice}

  """
  @spec notice_ok(Interval.t(), map() | nil, DateTime.t()) ::
          :ok | {:error, :not_allowed | :min_notice}
  def notice_ok(_, nil, _), do: :ok
  def notice_ok(_, %{allowed: false}, _), do: {:error, :not_allowed}

  def notice_ok(%Interval{} = existing, %{min_notice_min: min_notice_min}, %DateTime{} = now) do
    if DateTime.compare(DateTime.add(now, min_notice_min, :minute), existing.start_at) == :gt do
      {:error, :min_notice}
    else
      :ok
    end
  end

  defp lead_time_violation(slot, rule, now) do
    earliest = DateTime.add(now, rule.lead_time_min, :minute)
    seconds_short = DateTime.diff(earliest, slot.start_at, :second)

    if seconds_short > 0, do: {:lead_time, ceil_div(seconds_short, 60)}
  end

  defp booking_window_violation(_, %AvailabilityRule{booking_window_days: nil}, _), do: nil

  defp booking_window_violation(slot, rule, now) do
    last_date = Date.add(today(rule.timezone, now), rule.booking_window_days)
    slot_date = local_date(slot.start_at, rule.timezone)

    if Date.compare(slot_date, last_date) == :gt, do: {:outside_window, slot_date}
  end

  defp daily_cap_violation(_, %AvailabilityRule{max_per_day: nil}, _), do: nil

  defp daily_cap_violation(slot, rule, resource) do
    slot_date = local_date(slot.start_at, rule.timezone)
    count = Map.get(resource.daily_booking_counts, slot_date, 0)

    if count >= rule.max_per_day, do: {:daily_cap, resource.id, slot_date}
  end

  defp today(timezone, now), do: local_date(now, timezone)

  defp local_date(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
