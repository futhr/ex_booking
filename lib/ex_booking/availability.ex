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
  alias ExBooking.Resource
  alias ExBooking.Schedule
  alias ExBooking.Slotting

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

    with {:ok, pairs} <- pair(resources, rules) do
      {:ok, combine(meeting_type, pairs, from, until, now, slotting_opts(opts))}
    end
  end

  @doc """
  Checks a specific requested slot against conflict and policy for a meeting
  type, without committing to an assignment. Returns `:ok`, or
  `{:error, reasons}` with every failing reason.
  """
  @spec validate(Request.t(), MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          :ok | {:error, [term()]}
  def validate(%Request{} = request, %MeetingType{} = meeting_type, resources, rules, opts) do
    case eligible(request, meeting_type, resources, rules, Keyword.fetch!(opts, :now)) do
      {:ok, _free} -> :ok
      {:error, reasons} -> {:error, reasons}
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
          {:ok, [Resource.t()]} | {:error, [term()]}
  def eligible(%Request{slot: nil}, %MeetingType{}, _resources, _rules, _now) do
    {:error, [{:invalid, :slot, :missing}]}
  end

  def eligible(
        %Request{slot: %Interval{} = slot} = request,
        %MeetingType{} = meeting_type,
        resources,
        rules,
        %DateTime{} = now
      ) do
    case pair(resources, rules) do
      {:ok, pairs} ->
        pairs
        |> candidates(request.preferred_resource_ids)
        |> screen(meeting_type, slot, now)

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  defp combine(
         %MeetingType{participants: :one} = meeting_type,
         pairs,
         from,
         until,
         now,
         slotting_opts
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
         from,
         until,
         now,
         slotting_opts
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
         from,
         until,
         now,
         slotting_opts
       ) do
    offerables =
      Enum.map(pairs, fn {resource, rule} ->
        {:ok, offerable} = Schedule.expand(rule, from, until)
        {resource, rule, offerable}
      end)

    offerables
    |> Enum.flat_map(fn {_resource, _rule, offerable} ->
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

    resource.busy
    |> Interval.merge()
    |> Enum.map(&Interval.inflate(&1, after_min, before_min))
  end

  defp intersect_all([]), do: []
  defp intersect_all([first | rest]), do: Enum.reduce(rest, first, &intersect/2)

  defp intersect(as, bs) do
    for(a <- as, b <- bs, clipped = Interval.clip(a, b), clipped != nil, do: clipped)
    |> Interval.merge()
  end

  defp screen([], _meeting_type, slot, _now), do: {:error, [{:no_eligible_resource, slot}]}

  defp screen(candidates, %MeetingType{participants: :one} = meeting_type, slot, now) do
    {free, reasons} =
      Enum.reduce(candidates, {[], []}, fn {resource, rule}, {free, reasons} ->
        case failures(slot, resource, meeting_type, rule, now) do
          [] -> {[resource | free], reasons}
          resource_reasons -> {free, reasons ++ resource_reasons}
        end
      end)

    case free do
      [] -> {:error, Enum.uniq(reasons)}
      _free -> {:ok, Enum.reverse(free)}
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
      {:ok, Enum.map(candidates, fn {resource, _rule} -> resource end)}
    else
      {:error, reasons}
    end
  end

  defp screen(candidates, %MeetingType{participants: :pool} = meeting_type, slot, now) do
    {seats, free, reasons} =
      Enum.reduce(candidates, {0, [], []}, fn {resource, rule}, acc ->
        merge_contribution(pool_contribution(resource, rule, slot, meeting_type, now), acc)
      end)

    if seats >= meeting_type.capacity_required do
      {:ok, Enum.reverse(free)}
    else
      {:error, pool_reasons(reasons, slot)}
    end
  end

  defp pool_contribution(resource, rule, slot, meeting_type, now) do
    case Policy.violations(slot, rule, resource, now) do
      [] -> seat_contribution(resource, available_seats(resource, meeting_type, rule, slot), slot)
      policy_reasons -> {0, nil, policy_reasons}
    end
  end

  defp seat_contribution(resource, 0, slot), do: {0, nil, [{:conflict, resource.id, slot}]}
  defp seat_contribution(resource, seats, _slot), do: {seats, resource, []}

  defp merge_contribution({seats, nil, reasons}, {total, free, acc}),
    do: {total + seats, free, acc ++ reasons}

  defp merge_contribution({seats, resource, _reasons}, {total, free, acc}),
    do: {total + seats, [resource | free], acc}

  defp pool_reasons([], slot), do: [{:no_eligible_resource, slot}]
  defp pool_reasons(reasons, _slot), do: Enum.uniq(reasons)

  defp failures(slot, resource, meeting_type, rule, now) do
    conflicts(slot, resource, meeting_type, rule) ++ Policy.violations(slot, rule, resource, now)
  end

  defp conflicts(slot, resource, meeting_type, rule) do
    %{before_min: before_min, after_min: after_min} = effective_buffers(meeting_type, rule)
    inflated = Interval.inflate(slot, before_min, after_min)

    resource.busy
    |> Enum.filter(&Interval.overlaps?(inflated, &1))
    |> Enum.map(&{:conflict, resource.id, &1})
  end

  defp available_seats(resource, meeting_type, rule, slot) do
    %{before_min: before_min, after_min: after_min} = effective_buffers(meeting_type, rule)
    inflated = Interval.inflate(slot, before_min, after_min)
    overlapping = Enum.count(resource.busy, &Interval.overlaps?(inflated, &1))

    max(resource.capacity - overlapping, 0)
  end

  defp step(%MeetingType{slot_interval_min: nil, duration_min: duration}), do: duration
  defp step(%MeetingType{slot_interval_min: step}), do: step

  defp slotting_opts(opts), do: [align: Keyword.get(opts, :align, :free_start)]

  defp candidates(pairs, []), do: pairs

  defp candidates(pairs, ids),
    do: Enum.filter(pairs, fn {resource, _rule} -> resource.id in ids end)

  defp effective_buffers(%MeetingType{buffers: nil}, rule), do: rule.buffers
  defp effective_buffers(%MeetingType{buffers: buffers}, _rule), do: buffers

  defp pair(resources, rules) when length(resources) == length(rules) do
    {:ok, Enum.zip(resources, rules)}
  end

  defp pair(_resources, _rules), do: {:error, {:invalid, :rules, :length_mismatch}}
end
