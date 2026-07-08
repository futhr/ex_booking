defmodule ExBooking do
  @moduledoc """
  A pure booking kernel for sales scheduling.

  ExBooking answers deterministic questions — what slots are valid, does this
  request conflict, which resource takes it, what side effects must happen
  next — as pure functions over immutable inputs. No database, no processes,
  no I/O, no clock: `:now` is always a caller-supplied option.

  This module is the supported entry point; `ExBooking.Interval` and
  `ExBooking.Slotting` are public for lower-level needs. The normative
  specification lives in `docs/specs/` — start with spec 00 (overview) and
  spec 02 (public API).

  The full v0.1–v0.3 surface is implemented: availability assembly, slot
  validation, assignment strategies, and the booking lifecycle (decide,
  reschedule, cancellation). Standards interop covers dependency-free
  RRULE/ICS/JSCalendar helpers per `docs/specs/SP.07-roadmap.md`.
  """

  alias ExBooking.Assignment
  alias ExBooking.Availability
  alias ExBooking.AvailabilityRule
  alias ExBooking.Decision
  alias ExBooking.Event
  alias ExBooking.Hold
  alias ExBooking.ICalendar
  alias ExBooking.Interval
  alias ExBooking.JSCalendar
  alias ExBooking.MeetingType
  alias ExBooking.Policy
  alias ExBooking.Request
  alias ExBooking.Resource
  alias ExBooking.RRule

  @search_opts NimbleOptions.new!(
                 now: [type: {:struct, DateTime}, required: true],
                 from: [type: {:struct, DateTime}, required: true],
                 until: [type: {:struct, DateTime}, required: true],
                 strategy: [
                   type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
                   default: :first_available
                 ],
                 scorer: [type: {:fun, 2}],
                 align: [type: {:in, [:free_start, :clock]}, default: :free_start]
               )

  @decide_opts NimbleOptions.new!(
                 now: [type: {:struct, DateTime}, required: true],
                 strategy: [
                   type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
                   default: :first_available
                 ],
                 scorer: [type: {:fun, 2}],
                 hold: [type: {:struct, ExBooking.Hold}],
                 release_hold_id: [type: :string]
               )

  @now_opts NimbleOptions.new!(now: [type: {:struct, DateTime}, required: true])

  @rrule_opts NimbleOptions.new!(
                from: [type: {:struct, DateTime}, required: true],
                until: [type: {:struct, DateTime}, required: true]
              )

  @doc """
  Runs the full availability pipeline (spec 03 §3) and returns bookable
  slots sorted ascending by start.

  ## Options

    * `:now` (required) — the caller's current time
    * `:from`, `:until` (required) — search horizon
    * `:align` — `:free_start` (default) or `:clock`
    * `:strategy`, `:scorer` — see `ExBooking.Assignment`

  """
  @spec available_slots(MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def available_slots(%MeetingType{} = meeting_type, resources, rules, opts) do
    with {:ok, opts} <- validate_opts(opts, @search_opts) do
      Availability.assemble(meeting_type, resources, rules, opts)
    end
  end

  @doc """
  Checks a specific requested slot against availability and policy without
  committing to an assignment. Returns every failing reason, not just the
  first.
  """
  @spec validate_request(
          Request.t(),
          MeetingType.t(),
          [Resource.t()],
          [AvailabilityRule.t()],
          keyword()
        ) :: :ok | {:error, [term()] | term()}
  def validate_request(
        %Request{} = request,
        %MeetingType{} = meeting_type,
        resources,
        rules,
        opts
      ) do
    with {:ok, opts} <- validate_opts(opts, @decide_opts) do
      Availability.validate(request, meeting_type, resources, rules, opts)
    end
  end

  @doc """
  The core entry point: validate, assign, and produce a full
  `ExBooking.Decision` with events and side-effect intents.

  A decision is returned even for rejections (`status: :conflict` or
  `:policy_reject`); `{:error, _}` is reserved for malformed input.
  """
  @spec decide(Request.t(), MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          {:ok, Decision.t()} | {:error, term()}
  def decide(%Request{} = request, %MeetingType{} = meeting_type, resources, rules, opts) do
    with {:ok, opts} <- validate_opts(opts, @decide_opts) do
      {:ok, decision(request, meeting_type, resources, rules, opts, nil)}
    end
  end

  @doc """
  Like `decide/5`, but evaluates the reschedule policy against `existing`,
  treats the existing slot's busy time as released, and emits
  `:booking_rescheduled` semantics.
  """
  @spec reschedule(
          Interval.t(),
          Request.t(),
          MeetingType.t(),
          [Resource.t()],
          [AvailabilityRule.t()],
          keyword()
        ) :: {:ok, Decision.t()} | {:error, term()}
  def reschedule(
        %Interval{} = existing,
        %Request{} = request,
        %MeetingType{} = meeting_type,
        resources,
        rules,
        opts
      ) do
    with {:ok, opts} <- validate_opts(opts, @decide_opts) do
      case Policy.notice_ok(existing, meeting_type.reschedule_policy, opts[:now]) do
        :ok ->
          released = Enum.map(resources, &release_busy(&1, existing))
          {:ok, decision(request, meeting_type, released, rules, opts, {existing, request.slot})}

        {:error, reason} ->
          {:ok,
           %Decision{
             status: :policy_reject,
             slot: request.slot,
             reasons: [{:policy, :reschedule, reason}]
           }}
      end
    end
  end

  @doc """
  Pure cancellation-policy check for an existing booking against `:now`.
  Refund and fee semantics are consumer concerns layered on the result.
  """
  @spec evaluate_cancellation(Interval.t(), MeetingType.t(), keyword()) ::
          {:ok, %{allowed?: boolean(), reason: atom() | nil}} | {:error, term()}
  def evaluate_cancellation(%Interval{} = existing, %MeetingType{} = meeting_type, opts) do
    with {:ok, opts} <- validate_opts(opts, @now_opts) do
      result =
        case Policy.notice_ok(existing, meeting_type.cancellation_policy, opts[:now]) do
          :ok -> %{allowed?: true, reason: nil}
          {:error, reason} -> %{allowed?: false, reason: reason}
        end

      {:ok, result}
    end
  end

  @doc """
  Standalone assignment over pre-filtered free resources, for consumers that
  run their own availability search. See `ExBooking.Assignment`.
  """
  @spec assign([Resource.t()], Interval.t(), keyword()) ::
          {:ok, [Resource.t()]} | {:error, :no_eligible_resource}
  defdelegate assign(resources, slot, opts), to: Assignment

  @doc """
  Expands a supported RFC 5545 RRULE subset into UTC intervals over a caller
  supplied horizon.

  Supported rule parts are documented in `ExBooking.RRule`.
  """
  @spec expand_rrule(String.t() | RRule.t(), DateTime.t(), pos_integer(), keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def expand_rrule(rrule, %DateTime{} = dtstart, duration_min, opts) do
    with {:ok, opts} <- validate_opts(opts, @rrule_opts) do
      RRule.expand(rrule, dtstart, duration_min, opts[:from], opts[:until])
    end
  end

  @doc """
  Normalizes iCalendar `FREEBUSY` periods into busy intervals.

  This is a pure parser over caller-supplied iCalendar text. It performs no file
  or network I/O.
  """
  @spec import_ics_free_busy(String.t()) :: {:ok, [Interval.t()]} | {:error, term()}
  defdelegate import_ics_free_busy(ics), to: ICalendar, as: :free_busy

  @doc """
  Normalizes a decoded JSCalendar `Event` or `Group` into busy intervals.

  This is a pure mapper over caller-supplied maps. JSON decoding and recurrence
  expansion remain consumer concerns.
  """
  @spec import_jscalendar_busy(map()) :: {:ok, [Interval.t()]} | {:error, term()}
  defdelegate import_jscalendar_busy(object), to: JSCalendar, as: :busy_intervals

  # `reschedule` is nil for decide/5, or `{existing, new}` for reschedule/6.
  defp decision(request, meeting_type, resources, rules, opts, reschedule) do
    case Availability.eligible(request, meeting_type, resources, rules, opts[:now]) do
      {:ok, free} -> assign_decision(request, meeting_type, free, opts, reschedule)
      {:error, reasons} -> rejected_decision(request, reasons)
    end
  end

  defp assign_decision(request, meeting_type, free, opts, reschedule) do
    assign_opts = [
      strategy: opts[:strategy],
      scorer: opts[:scorer],
      routing_context: request.routing_context,
      participants: meeting_type.participants,
      capacity_required: meeting_type.capacity_required
    ]

    case Assignment.assign(free, request.slot, assign_opts) do
      {:ok, winners} ->
        success_decision(request, meeting_type, winners, opts, reschedule)

      {:error, :no_eligible_resource} ->
        rejected_decision(request, [{:no_eligible_resource, request.slot}])
    end
  end

  defp success_decision(request, meeting_type, winners, opts, reschedule) do
    resource_ids = Enum.map(winners, & &1.id)

    event = %Event{
      type: event_type(opts, reschedule),
      slot: request.slot,
      resource_ids: resource_ids,
      meeting_type_id: meeting_type.id,
      routing_context: request.routing_context,
      data: event_data(reschedule)
    }

    %Decision{
      status: :ok,
      slot: request.slot,
      resource_ids: resource_ids,
      events: [event],
      intents: intents(event, opts, reschedule, resource_ids, meeting_type)
    }
  end

  defp event_type(_opts, {_existing, _new}), do: :booking_rescheduled
  defp event_type(opts, nil), do: if(opts[:hold], do: :booking_reserved, else: :booking_confirmed)

  defp event_data(nil), do: %{}
  defp event_data({existing, new}), do: %{from: existing, to: new}

  # Intents are ordered persist-first: reserve/release before calendar/emit (SP.05).
  defp intents(event, opts, nil, resource_ids, meeting_type) do
    case opts[:hold] do
      %Hold{} = hold ->
        [{:reserve, hold}, {:emit, event}]

      nil ->
        [
          {:calendar_event, :create, calendar_payload(event, resource_ids, meeting_type)},
          {:emit, event}
        ]
    end
  end

  defp intents(event, opts, {_existing, _new}, resource_ids, meeting_type) do
    release =
      case opts[:release_hold_id] do
        nil -> []
        hold_id -> [{:release, hold_id}]
      end

    release ++
      [
        {:calendar_event, :move, calendar_payload(event, resource_ids, meeting_type)},
        {:emit, event}
      ]
  end

  defp calendar_payload(event, resource_ids, meeting_type) do
    %{slot: event.slot, resource_ids: resource_ids, meeting_type_id: meeting_type.id}
  end

  defp rejected_decision(request, reasons) do
    %Decision{status: rejection_status(reasons), slot: request.slot, reasons: reasons}
  end

  defp rejection_status(reasons) do
    cond do
      Enum.any?(reasons, &match?({:no_eligible_resource, _slot}, &1)) -> :needs_routing
      Enum.any?(reasons, &match?({:conflict, _resource_id, _interval}, &1)) -> :conflict
      true -> :policy_reject
    end
  end

  defp release_busy(resource, existing) do
    %{resource | busy: Interval.subtract_all(resource.busy, [existing])}
  end

  defp validate_opts(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, error} -> {:error, {:invalid, :opts, Exception.message(error)}}
    end
  end
end
