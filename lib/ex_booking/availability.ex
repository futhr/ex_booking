defmodule ExBooking.Availability do
  @moduledoc """
  Availability assembly and eligibility checks.

  This module expands each resource's offerable wall time, subtracts busy time
  with buffers, generates candidate slots, applies policy predicates, and
  combines results according to the meeting participant mode.

  Resources and rules are paired by position. `:one` offers slots for any free
  resource, `:collective` requires every resource to be free, and `:pool`
  offers slots while enough seats remain across capacity-aware resources.

  ## Example

      iex> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...> resource = %ExBooking.Resource{id: "host_1", timezone: "Etc/UTC"}
      ...>
      ...> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> {:ok, [slot, _]} =
      ...>   ExBooking.Availability.assemble(meeting_type, [resource], [rule],
      ...>     now: ~U[2026-07-08 12:00:00Z],
      ...>     from: ~U[2026-07-13 00:00:00Z],
      ...>     until: ~U[2026-07-13 23:59:59Z]
      ...>   )
      ...>
      ...> slot.start_at
      ~U[2026-07-13 09:00:00Z]

  """

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Policy
  alias ExBooking.Request
  alias ExBooking.Reservation
  alias ExBooking.Resource
  alias ExBooking.Schedule
  alias ExBooking.Slotting

  @fairness_fields [:assignments_count, :last_assigned_at, :weight, :priority]

  @doc """
  Assembles bookable slots for a meeting type over a search horizon.

  Requires `:now`, `:from`, and `:until` in `opts`. Returns slots sorted
  ascending by `start_at`, deduplicated across resources.
  """
  @spec assemble(MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def assemble(%MeetingType{} = meeting_type, resources, rules, opts) do
    now = Keyword.fetch!(opts, :now)
    from = Keyword.fetch!(opts, :from)
    until = Keyword.fetch!(opts, :until)

    with :ok <- validate_inputs(meeting_type, resources, rules),
         {:ok, pairs} <- pair(resources, rules) do
      {:ok, combine(meeting_type, pairs, {from, until, now, slotting_opts(opts)})}
    end
  end

  @doc """
  Validates meeting, resource, and rule inputs used by availability operations.

  This preflight keeps hand-built malformed structs away from temporal
  arithmetic, timezone conversion, assignment, and slot generation.

  ## Example

      iex> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...> resource = %ExBooking.Resource{id: "host_1", timezone: "Etc/UTC"}
      ...> rule = %ExBooking.AvailabilityRule{timezone: "Etc/UTC", windows: []}
      ...> ExBooking.Availability.validate_inputs(meeting_type, [resource], [rule])
      :ok

  """
  @spec validate_inputs(MeetingType.t(), [Resource.t()], [AvailabilityRule.t()]) ::
          :ok | {:error, {:invalid, atom(), term()}}
  def validate_inputs(%MeetingType{} = meeting_type, resources, rules) do
    with :ok <- validate_meeting_type(meeting_type),
         :ok <- validate_resources(resources),
         :ok <- validate_rules(rules),
         {:ok, _} <- pair(resources, rules) do
      :ok
    end
  end

  @doc """
  Checks a specific requested slot against conflict and policy for a meeting
  type, without committing to an assignment. Returns `:ok`, or
  `{:error, reasons}` with every failing reason.
  """
  @spec validate(Request.t(), MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          :ok | {:error, [term()] | {:invalid, atom(), term()}}
  def validate(%Request{} = request, %MeetingType{} = meeting_type, resources, rules, opts) do
    case eligible(request, meeting_type, resources, rules, Keyword.fetch!(opts, :now)) do
      {:ok, _} -> :ok
      {:error, reasons} -> {:error, reasons}
    end
  end

  @doc """
  Validates the structural relationship between a request and meeting type.

  This check is independent of resource availability and returns a tagged
  malformed-input error rather than booking rejection reasons.

  ## Example

      iex> slot = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> request = %ExBooking.Request{
      ...>   meeting_type_id: "intro",
      ...>   invitee_timezone: "Etc/UTC",
      ...>   slot: slot
      ...> }
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...> ExBooking.Availability.validate_request_shape(request, meeting_type)
      :ok

  """
  @spec validate_request_shape(Request.t(), MeetingType.t()) ::
          :ok | {:error, {:invalid, atom(), term()}}
  def validate_request_shape(%Request{} = request, %MeetingType{} = meeting_type) do
    with :ok <- validate_meeting_type(meeting_type),
         :ok <- validate_request(request) do
      validate_request_fields(request, meeting_type)
    end
  end

  @doc """
  Validates a meeting type's complete kernel-facing shape.

  ## Examples

      iex> ExBooking.Availability.validate_meeting_type(%ExBooking.MeetingType{
      ...>   id: "intro",
      ...>   duration_min: 30
      ...> })
      :ok

  """
  @spec validate_meeting_type(MeetingType.t()) :: :ok | {:error, {:invalid, atom(), term()}}
  def validate_meeting_type(%MeetingType{id: id}) when not is_binary(id) or id == "",
    do: {:error, {:invalid, :meeting_type_id, id}}

  def validate_meeting_type(%MeetingType{duration_min: duration})
      when not is_integer(duration) or duration <= 0,
      do: {:error, {:invalid, :duration_min, duration}}

  def validate_meeting_type(%MeetingType{slot_interval_min: step})
      when step != nil and (not is_integer(step) or step <= 0),
      do: {:error, {:invalid, :slot_interval_min, step}}

  def validate_meeting_type(%MeetingType{capacity_required: capacity})
      when not is_integer(capacity) or capacity <= 0,
      do: {:error, {:invalid, :capacity_required, capacity}}

  def validate_meeting_type(%MeetingType{participants: participants})
      when participants not in [:one, :collective, :pool],
      do: {:error, {:invalid, :participants, participants}}

  def validate_meeting_type(%MeetingType{} = meeting_type) do
    with :ok <- validate_buffers(meeting_type.buffers, :meeting_buffers),
         :ok <- Policy.validate(meeting_type.cancellation_policy, :cancellation_policy) do
      Policy.validate(meeting_type.reschedule_policy, :reschedule_policy)
    end
  end

  @doc """
  Returns the resources eligible to take the request's slot — free of conflict
  and policy violations, and satisfying the participant mode — or
  `{:error, reasons}` aggregating every failing reason. Drives both
  `validate/5` and `ExBooking.decide/5`.
  """
  @spec eligible(
          Request.t(),
          MeetingType.t(),
          [Resource.t()],
          [AvailabilityRule.t()],
          DateTime.t()
        ) ::
          {:ok, [Resource.t()]} | {:error, [term()] | {:invalid, atom(), term()}}

  def eligible(
        %Request{slot: %Interval{} = slot} = request,
        %MeetingType{} = meeting_type,
        resources,
        rules,
        %DateTime{} = now
      ) do
    with :ok <- validate_request_shape(request, meeting_type),
         :ok <- validate_inputs(meeting_type, resources, rules) do
      case pair(resources, rules) do
        {:ok, pairs} ->
          pairs
          |> candidates(request.preferred_resource_ids)
          |> screen(meeting_type, slot, now)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def eligible(%Request{} = request, %MeetingType{} = meeting_type, _, _, %DateTime{}) do
    case validate_request_shape(request, meeting_type) do
      {:error, _} = error -> error
      :ok -> {:error, {:invalid, :slot, :invalid_interval}}
    end
  end

  defp combine(
         %MeetingType{participants: :one} = meeting_type,
         pairs,
         {from, until, now, slotting_opts}
       ) do
    pairs
    |> Enum.flat_map(fn {resource, rule} ->
      resource_slots(meeting_type, resource, rule, {from, until, now}, slotting_opts)
    end)
    |> Enum.uniq_by(& &1.start_at)
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  defp combine(
         %MeetingType{participants: :collective} = meeting_type,
         pairs,
         {from, until, now, slotting_opts}
       ) do
    pairs
    |> Enum.map(fn {resource, rule} ->
      resource_free(meeting_type, resource, rule, from, until)
    end)
    |> intersect_all()
    |> Slotting.generate_all(meeting_type.duration_min, step(meeting_type), slotting_opts)
    |> Enum.filter(&all_pass_policy?(pairs, &1, now))
  end

  defp combine(
         %MeetingType{participants: :pool} = meeting_type,
         pairs,
         {from, until, now, slotting_opts}
       ) do
    offerables =
      Enum.map(pairs, fn {resource, rule} ->
        {:ok, offerable} = Schedule.expand(rule, from, until)
        {resource, rule, offerable}
      end)

    offerables
    |> Enum.flat_map(fn {_, _, offerable} ->
      Slotting.generate_all(
        offerable,
        meeting_type.duration_min,
        step(meeting_type),
        slotting_opts
      )
    end)
    |> Enum.uniq_by(& &1.start_at)
    |> Enum.sort_by(& &1.start_at, DateTime)
    |> Enum.filter(
      &(offered_seats(offerables, meeting_type, &1, now) >= meeting_type.capacity_required)
    )
  end

  defp resource_slots(meeting_type, resource, rule, {from, until, now}, slotting_opts) do
    meeting_type
    |> resource_free(resource, rule, from, until)
    |> Slotting.generate_all(meeting_type.duration_min, step(meeting_type), slotting_opts)
    |> Enum.filter(&(Policy.violations(&1, rule, resource, now) == []))
  end

  defp resource_free(meeting_type, resource, rule, from, until) do
    {:ok, offerable} = Schedule.expand(rule, from, until)
    Interval.subtract_all(offerable, inflated_busy(resource, meeting_type, rule))
  end

  defp all_pass_policy?(pairs, slot, now) do
    Enum.all?(pairs, fn {resource, rule} -> Policy.violations(slot, rule, resource, now) == [] end)
  end

  defp offered_seats(offerables, meeting_type, slot, now) do
    Enum.reduce(offerables, 0, fn {resource, rule, offerable}, total ->
      if offerable?(offerable, slot) and Policy.violations(slot, rule, resource, now) == [] do
        total + available_seats(resource, meeting_type, rule, slot)
      else
        total
      end
    end)
  end

  defp offerable?(offerable, slot), do: Enum.any?(offerable, &Interval.contains?(&1, slot))

  defp inflated_busy(resource, meeting_type, rule) do
    %{before_min: before_min, after_min: after_min} = effective_buffers(meeting_type, rule)

    (resource.busy ++ Enum.map(resource.reservations, & &1.interval))
    |> Interval.merge()
    |> Enum.map(&Interval.inflate(&1, after_min, before_min))
  end

  defp intersect_all([]), do: []
  defp intersect_all([first | rest]), do: Enum.reduce(rest, first, &intersect/2)

  defp intersect(as, bs), do: Interval.intersect(as, bs)

  defp screen([], _, slot, _), do: {:error, [{:no_eligible_resource, slot}]}

  defp screen(candidates, %MeetingType{participants: :one} = meeting_type, slot, now) do
    {free, reasons_rev} =
      Enum.reduce(candidates, {[], []}, fn {resource, rule}, {free, reasons} ->
        case failures(slot, resource, meeting_type, rule, now) do
          [] -> {[resource | free], reasons}
          resource_reasons -> {free, Enum.reverse(resource_reasons, reasons)}
        end
      end)

    reasons = Enum.reverse(reasons_rev)

    case free do
      [] -> {:error, Enum.uniq(reasons)}
      _ -> {:ok, Enum.reverse(free)}
    end
  end

  defp screen(candidates, %MeetingType{participants: :collective} = meeting_type, slot, now) do
    reasons =
      candidates
      |> Enum.flat_map(fn {resource, rule} ->
        failures(slot, resource, meeting_type, rule, now)
      end)
      |> Enum.uniq()

    if reasons == [] do
      {:ok, Enum.map(candidates, fn {resource, _} -> resource end)}
    else
      {:error, reasons}
    end
  end

  defp screen(candidates, %MeetingType{participants: :pool} = meeting_type, slot, now) do
    {seats, free, reasons_rev} =
      Enum.reduce(candidates, {0, [], []}, fn {resource, rule}, acc ->
        merge_contribution(pool_contribution(resource, rule, slot, meeting_type, now), acc)
      end)

    if seats >= meeting_type.capacity_required do
      {:ok, Enum.reverse(free)}
    else
      {:error, pool_reasons(Enum.reverse(reasons_rev), slot)}
    end
  end

  defp pool_contribution(resource, rule, slot, meeting_type, now) do
    case offerability_failures(slot, rule) ++ Policy.violations(slot, rule, resource, now) do
      [] -> seat_contribution(resource, available_seats(resource, meeting_type, rule, slot), slot)
      policy_reasons -> {0, nil, policy_reasons}
    end
  end

  defp seat_contribution(resource, 0, slot), do: {0, nil, [{:conflict, resource.id, slot}]}
  defp seat_contribution(resource, seats, _), do: {seats, %{resource | capacity: seats}, []}

  defp merge_contribution({seats, nil, reasons}, {total, free, acc}),
    do: {total + seats, free, Enum.reverse(reasons, acc)}

  defp merge_contribution({seats, resource, _}, {total, free, acc}),
    do: {total + seats, [resource | free], acc}

  defp pool_reasons([], slot), do: [{:no_eligible_resource, slot}]
  defp pool_reasons(reasons, _), do: Enum.uniq(reasons)

  defp failures(slot, resource, meeting_type, rule, now) do
    offerability_failures(slot, rule) ++
      conflicts(slot, resource, meeting_type, rule) ++
      Policy.violations(slot, rule, resource, now)
  end

  defp offerability_failures(slot, rule) do
    {:ok, offerable} = Schedule.expand(rule, slot.start_at, slot.end_at)

    if offerable?(offerable, slot) do
      []
    else
      local_date =
        slot.start_at
        |> DateTime.shift_zone!(rule.timezone)
        |> DateTime.to_date()

      [{:outside_window, local_date}]
    end
  end

  defp validate_request_fields(
         %Request{meeting_type_id: request_id},
         %MeetingType{id: meeting_type_id}
       )
       when request_id != meeting_type_id do
    {:error, {:invalid, :meeting_type_id, {:mismatch, request_id, meeting_type_id}}}
  end

  defp validate_request_fields(%Request{}, %MeetingType{duration_min: duration})
       when not is_integer(duration) or duration <= 0 do
    {:error, {:invalid, :duration_min, duration}}
  end

  defp validate_request_fields(%Request{slot: nil}, %MeetingType{}) do
    {:error, {:invalid, :slot, :required}}
  end

  defp validate_request_fields(
         %Request{
           slot: %Interval{start_at: %DateTime{} = start_at, end_at: %DateTime{} = end_at} = slot
         },
         %MeetingType{duration_min: duration}
       ) do
    case Interval.validate(slot) do
      :ok -> validate_slot_duration(start_at, end_at, duration)
      {:error, {:invalid, :interval, detail}} -> {:error, {:invalid, :slot, detail}}
    end
  end

  defp validate_request_fields(%Request{}, %MeetingType{}) do
    {:error, {:invalid, :slot, :invalid_interval}}
  end

  defp validate_resources(resources) when is_list(resources) do
    resources
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%Resource{} = resource, _}, :ok ->
        case validate_resource(resource) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end

      {resource, index}, :ok ->
        {:halt, {:error, {:invalid, :resources, {:at, index, resource}}}}
    end)
  end

  defp validate_resources(resources), do: {:error, {:invalid, :resources, resources}}

  defp validate_resource(%Resource{id: id}) when not is_binary(id) or id == "",
    do: {:error, {:invalid, :resource_id, id}}

  defp validate_resource(%Resource{id: id, timezone: timezone, capacity: capacity} = resource) do
    with :ok <- validate_resource_timezone(id, timezone),
         :ok <- validate_resource_capacity(id, capacity),
         :ok <- validate_busy(id, resource.busy),
         :ok <- validate_reservations(id, resource.reservations),
         :ok <- validate_daily_counts(id, resource.daily_booking_counts) do
      validate_fairness(id, resource.fairness)
    end
  end

  defp validate_resource_timezone(id, timezone) when not is_binary(timezone),
    do: {:error, {:invalid, :resource_timezone, {id, timezone}}}

  defp validate_resource_timezone(id, timezone) do
    case DateTime.shift_zone(~U[2026-01-01 00:00:00Z], timezone) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, {:invalid, :resource_timezone, {id, timezone}}}
    end
  end

  defp validate_resource_capacity(id, capacity)
       when not is_integer(capacity) or capacity <= 0,
       do: {:error, {:invalid, :resource_capacity, {id, capacity}}}

  defp validate_resource_capacity(_, _), do: :ok

  defp validate_busy(id, busy) when is_list(busy) do
    validate_interval_list(busy, :resource_busy, id)
  end

  defp validate_busy(id, busy), do: {:error, {:invalid, :resource_busy, {id, busy}}}

  defp validate_interval_list(intervals, field, id) do
    intervals
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {interval, index}, :ok ->
      case Interval.validate(interval) do
        :ok ->
          {:cont, :ok}

        {:error, {:invalid, :interval, detail}} ->
          {:halt, {:error, {:invalid, field, {id, index, detail}}}}
      end
    end)
  end

  defp validate_reservations(id, reservations) when is_list(reservations) do
    reservations
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%Reservation{} = reservation, index}, :ok ->
        case validate_reservation(reservation) do
          :ok ->
            {:cont, :ok}

          {:error, detail} ->
            {:halt, {:error, {:invalid, :resource_reservations, {id, index, detail}}}}
        end

      {reservation, index}, :ok ->
        {:halt, {:error, {:invalid, :resource_reservations, {id, index, reservation}}}}
    end)
  end

  defp validate_reservations(id, value),
    do: {:error, {:invalid, :resource_reservations, {id, value}}}

  defp validate_reservation(%Reservation{interval: interval, capacity_consumed: consumed}) do
    with :ok <- unwrap_interval(Interval.validate(interval)),
         true <- is_integer(consumed) and consumed > 0 do
      :ok
    else
      false -> {:error, {:capacity_consumed, consumed}}
      {:error, detail} -> {:error, {:interval, detail}}
    end
  end

  defp unwrap_interval(:ok), do: :ok
  defp unwrap_interval({:error, {:invalid, :interval, detail}}), do: {:error, detail}

  defp validate_daily_counts(id, counts) when is_map(counts) and not is_struct(counts) do
    case Enum.find(counts, fn {date, count} ->
           not is_struct(date, Date) or not is_integer(count) or count < 0
         end) do
      nil -> :ok
      invalid -> {:error, {:invalid, :daily_booking_counts, {id, invalid}}}
    end
  end

  defp validate_daily_counts(id, counts),
    do: {:error, {:invalid, :daily_booking_counts, {id, counts}}}

  defp validate_fairness(_, nil), do: :ok

  defp validate_fairness(id, fairness) when is_map(fairness) and not is_struct(fairness) do
    invalid = Enum.find(fairness, &invalid_fairness?/1)

    if invalid,
      do: {:error, {:invalid, :resource_fairness, {id, invalid}}},
      else: :ok
  end

  defp validate_fairness(id, fairness),
    do: {:error, {:invalid, :resource_fairness, {id, fairness}}}

  defp invalid_fairness?({key, _}) when key not in @fairness_fields, do: true
  defp invalid_fairness?({:assignments_count, value}), do: not is_integer(value) or value < 0

  defp invalid_fairness?({:last_assigned_at, value}),
    do: value != nil and not is_struct(value, DateTime)

  defp invalid_fairness?({:weight, value}), do: not is_number(value) or value <= 0
  defp invalid_fairness?({:priority, value}), do: not is_integer(value)

  defp validate_request(%Request{meeting_type_id: id}) when not is_binary(id) or id == "",
    do: {:error, {:invalid, :meeting_type_id, id}}

  defp validate_request(%Request{invitee_timezone: timezone} = request) do
    with :ok <- validate_invitee_timezone(timezone),
         :ok <- validate_preferred_ids(request.preferred_resource_ids) do
      if is_map(request.routing_context) and not is_struct(request.routing_context),
        do: :ok,
        else: {:error, {:invalid, :routing_context, request.routing_context}}
    end
  end

  defp validate_invitee_timezone(timezone) when is_binary(timezone) and timezone != "" do
    case DateTime.shift_zone(~U[2026-01-01 00:00:00Z], timezone) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, {:invalid, :invitee_timezone, timezone}}
    end
  end

  defp validate_invitee_timezone(timezone),
    do: {:error, {:invalid, :invitee_timezone, timezone}}

  defp validate_preferred_ids(ids) when is_list(ids) do
    case Enum.find(ids, &(not is_binary(&1) or &1 == "")) do
      nil -> :ok
      invalid -> {:error, {:invalid, :preferred_resource_ids, invalid}}
    end
  end

  defp validate_preferred_ids(ids),
    do: {:error, {:invalid, :preferred_resource_ids, ids}}

  defp validate_buffers(nil, _), do: :ok

  defp validate_buffers(%{before_min: before_min, after_min: after_min} = buffers, _)
       when map_size(buffers) == 2 and is_integer(before_min) and before_min >= 0 and
              is_integer(after_min) and after_min >= 0,
       do: :ok

  defp validate_buffers(buffers, field), do: {:error, {:invalid, field, buffers}}

  defp validate_rules(rules) when is_list(rules) do
    rules
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%AvailabilityRule{} = rule, _}, :ok ->
        case Schedule.validate(rule) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end

      {rule, index}, :ok ->
        {:halt, {:error, {:invalid, :rules, {:at, index, rule}}}}
    end)
  end

  defp validate_rules(rules), do: {:error, {:invalid, :rules, rules}}

  defp validate_slot_duration(start_at, end_at, duration_min) do
    expected = duration_min * 60
    expected_microseconds = expected * 1_000_000
    actual_microseconds = DateTime.diff(end_at, start_at, :microsecond)

    if actual_microseconds == expected_microseconds do
      :ok
    else
      actual = seconds(actual_microseconds)
      {:error, {:invalid, :slot_duration, {:expected, expected, :actual, actual}}}
    end
  end

  defp seconds(microseconds) when rem(microseconds, 1_000_000) == 0,
    do: div(microseconds, 1_000_000)

  defp seconds(microseconds), do: microseconds / 1_000_000

  defp conflicts(slot, resource, meeting_type, rule) do
    %{before_min: before_min, after_min: after_min} = effective_buffers(meeting_type, rule)
    inflated = Interval.inflate(slot, before_min, after_min)

    (resource.busy ++ Enum.map(resource.reservations, & &1.interval))
    |> Enum.filter(&Interval.overlaps?(inflated, &1))
    |> Enum.map(&{:conflict, resource.id, &1})
  end

  defp available_seats(resource, meeting_type, rule, slot) do
    %{before_min: before_min, after_min: after_min} = effective_buffers(meeting_type, rule)
    inflated = Interval.inflate(slot, before_min, after_min)

    if Enum.any?(resource.busy, &Interval.overlaps?(inflated, &1)) do
      0
    else
      consumed = Enum.reduce(resource.reservations, 0, &consumed_capacity(&1, inflated, &2))
      max(resource.capacity - consumed, 0)
    end
  end

  defp consumed_capacity(
         %Reservation{interval: interval, capacity_consumed: consumed},
         inflated,
         total
       )
       when is_integer(consumed) and consumed > 0 do
    if Interval.overlaps?(inflated, interval), do: total + consumed, else: total
  end

  defp consumed_capacity(_, _, total), do: total

  defp step(%MeetingType{slot_interval_min: nil, duration_min: duration}), do: duration
  defp step(%MeetingType{slot_interval_min: step}), do: step

  defp slotting_opts(opts), do: [align: Keyword.get(opts, :align, :free_start)]

  defp candidates(pairs, []), do: pairs

  defp candidates(pairs, ids),
    do: Enum.filter(pairs, fn {resource, _} -> resource.id in ids end)

  defp effective_buffers(%MeetingType{buffers: nil}, rule), do: rule.buffers
  defp effective_buffers(%MeetingType{buffers: buffers}, _), do: buffers

  defp pair(resources, rules) when length(resources) == length(rules) do
    {:ok, Enum.zip(resources, rules)}
  end

  defp pair(_, _), do: {:error, {:invalid, :rules, :length_mismatch}}
end
