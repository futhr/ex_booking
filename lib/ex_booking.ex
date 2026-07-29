defmodule ExBooking do
  @moduledoc """
  Pure booking decisions for scheduling products.

  `ExBooking` is the facade for availability search, request validation,
  assignment, lifecycle transitions, and small calendar-data normalizers. The
  caller owns state and effects; this library only returns facts, events, and
  intents from explicit inputs.

  The important rule is that time is always supplied. Functions that depend on
  "now" require it in options, which makes decisions repeatable in tests,
  background jobs, and replayed workflows.

  ## Example

      iex> meeting_type = %ExBooking.MeetingType{
      ...>   id: "intro",
      ...>   duration_min: 30,
      ...>   slot_interval_min: 15
      ...> }
      ...>
      ...> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}
      ...>
      ...> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> {:ok, slots} =
      ...>   ExBooking.available_slots(meeting_type, [resource], [rule],
      ...>     now: ~U[2026-07-08 12:00:00Z],
      ...>     from: ~U[2026-07-13 00:00:00Z],
      ...>     until: ~U[2026-07-13 23:59:59Z]
      ...>   )
      ...>
      ...> Enum.map(slots, & &1.start_at)
      [~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:15:00Z], ~U[2026-07-13 09:30:00Z]]

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

  @validate_request_opts NimbleOptions.new!(
                           now: [type: {:struct, DateTime}, required: true],
                           strategy: [
                             type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
                             default: :first_available
                           ],
                           scorer: [type: {:fun, 2}],
                           from: [type: {:struct, DateTime}],
                           until: [type: {:struct, DateTime}]
                         )

  @decide_opts NimbleOptions.new!(
                 now: [type: {:struct, DateTime}, required: true],
                 strategy: [
                   type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
                   default: :first_available
                 ],
                 scorer: [type: {:fun, 2}],
                 hold: [type: {:struct, ExBooking.Hold}],
                 from: [type: {:struct, DateTime}],
                 until: [type: {:struct, DateTime}],
                 align: [type: {:in, [:free_start, :clock]}, default: :free_start],
                 alternatives_limit: [type: :non_neg_integer, default: 3]
               )

  @reschedule_opts NimbleOptions.new!(
                     now: [type: {:struct, DateTime}, required: true],
                     strategy: [
                       type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
                       default: :first_available
                     ],
                     scorer: [type: {:fun, 2}],
                     release_hold_id: [type: :string],
                     from: [type: {:struct, DateTime}],
                     until: [type: {:struct, DateTime}],
                     align: [type: {:in, [:free_start, :clock]}, default: :free_start],
                     alternatives_limit: [type: :non_neg_integer, default: 3]
                   )

  @now_opts NimbleOptions.new!(now: [type: {:struct, DateTime}, required: true])

  @cancel_opts NimbleOptions.new!(
                 now: [type: {:struct, DateTime}, required: true],
                 resource_ids: [type: {:list, :string}, default: []],
                 routing_context: [type: {:map, :any, :any}, default: %{}],
                 release_hold_id: [type: :string]
               )

  @transition_opts NimbleOptions.new!(
                     resource_ids: [type: {:list, :string}, default: []],
                     routing_context: [type: {:map, :any, :any}, default: %{}]
                   )

  @routing_context_opts NimbleOptions.new!(
                          routing_context: [type: {:map, :any, :any}, default: %{}]
                        )

  @rrule_opts NimbleOptions.new!(
                from: [type: {:struct, DateTime}, required: true],
                until: [type: {:struct, DateTime}, required: true]
              )

  @doc """
  Runs availability search and returns bookable slots sorted ascending by start.

  ## Options

    * `:now` (required) — the caller's current time
    * `:from`, `:until` (required) — search horizon
    * `:align` — `:free_start` (default) or `:clock`
    * `:strategy`, `:scorer` — see `ExBooking.Assignment`

  ## Example

      iex> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...>
      ...> ExBooking.available_slots(meeting_type, [], [],
      ...>   now: ~U[2026-07-08 12:00:00Z],
      ...>   from: ~U[2026-07-13 00:00:00Z],
      ...>   until: ~U[2026-07-14 00:00:00Z]
      ...> )
      {:ok, []}

  """
  @spec available_slots(MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def available_slots(%MeetingType{} = meeting_type, resources, rules, opts) do
    with :ok <- validate_horizon(opts, :required),
         {:ok, opts} <- validate_opts(opts, @search_opts),
         :ok <- Availability.validate_inputs(meeting_type, resources, rules),
         :ok <- Assignment.validate(resources, opts) do
      Availability.assemble(meeting_type, resources, rules, opts)
    end
  end

  @doc """
  Checks a specific requested slot against availability and policy without
  committing to an assignment. Returns every failing reason, not just the
  first.

  ## Example

      iex> slot =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...>
      ...> request = %ExBooking.Request{
      ...>   meeting_type_id: "intro",
      ...>   invitee_timezone: "Etc/UTC",
      ...>   slot: slot
      ...> }
      ...>
      ...> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}
      ...>
      ...> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> ExBooking.validate_request(request, meeting_type, [resource], [rule],
      ...>   now: ~U[2026-07-08 12:00:00Z]
      ...> )
      :ok

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
    with :ok <- validate_horizon(opts, :optional),
         {:ok, opts} <- validate_opts(opts, @validate_request_opts),
         :ok <- Availability.validate_request_shape(request, meeting_type),
         :ok <- Availability.validate_inputs(meeting_type, resources, rules),
         :ok <- Assignment.validate(resources, opts) do
      Availability.validate(request, meeting_type, resources, rules, opts)
    end
  end

  @doc """
  The core entry point: validate, assign, and produce a full
  `ExBooking.Decision` with events and side-effect intents.

  A decision is returned even for rejections (`status: :conflict` or
  `:policy_reject`); `{:error, _}` is reserved for malformed input.

  ## Example

      iex> slot =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...>
      ...> request = %ExBooking.Request{
      ...>   meeting_type_id: "intro",
      ...>   invitee_timezone: "Etc/UTC",
      ...>   slot: slot
      ...> }
      ...>
      ...> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}
      ...>
      ...> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> {:ok, decision} =
      ...>   ExBooking.decide(request, meeting_type, [resource], [rule],
      ...>     now: ~U[2026-07-08 12:00:00Z]
      ...>   )
      ...>
      ...> {decision.status, decision.resource_ids}
      {:ok, ["resource_1"]}

  """
  @spec decide(Request.t(), MeetingType.t(), [Resource.t()], [AvailabilityRule.t()], keyword()) ::
          {:ok, Decision.t()} | {:error, term()}
  def decide(%Request{} = request, %MeetingType{} = meeting_type, resources, rules, opts) do
    with :ok <- validate_horizon(opts, :optional),
         {:ok, opts} <- validate_opts(opts, @decide_opts),
         :ok <- Availability.validate_request_shape(request, meeting_type),
         :ok <- Availability.validate_inputs(meeting_type, resources, rules),
         :ok <- Assignment.validate(resources, opts) do
      decision(request, meeting_type, {resources, rules}, opts, nil)
    end
  end

  @doc """
  Like `decide/5`, but evaluates the reschedule policy against `existing` and
  emits `:booking_rescheduled` semantics. The caller must remove only the
  identified booking's own claims from `resources`; the kernel never subtracts
  generic busy intervals by timestamp.

  ## Example

      iex> existing =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 08:00:00Z],
      ...>     ~U[2026-07-13 08:30:00Z]
      ...>   )
      ...>
      ...> requested =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...>
      ...> request = %ExBooking.Request{
      ...>   meeting_type_id: "intro",
      ...>   invitee_timezone: "Etc/UTC",
      ...>   slot: requested
      ...> }
      ...>
      ...> resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}
      ...>
      ...> rule = %ExBooking.AvailabilityRule{
      ...>   timezone: "Etc/UTC",
      ...>   windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
      ...> }
      ...>
      ...> {:ok, decision} =
      ...>   ExBooking.reschedule(existing, request, meeting_type, [resource], [rule],
      ...>     now: ~U[2026-07-08 12:00:00Z]
      ...>   )
      ...>
      ...> hd(decision.events).type
      :booking_rescheduled

  """
  @spec reschedule(
          Interval.t(),
          Request.t(),
          MeetingType.t(),
          [Resource.t()],
          [AvailabilityRule.t()],
          keyword()
        ) :: {:ok, Decision.t()} | {:error, term()}
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def reschedule(
        existing,
        %Request{} = request,
        %MeetingType{} = meeting_type,
        resources,
        rules,
        opts
      ) do
    with :ok <- validate_horizon(opts, :optional),
         {:ok, opts} <- validate_opts(opts, @reschedule_opts),
         :ok <- validate_existing(existing),
         :ok <- Availability.validate_request_shape(request, meeting_type),
         :ok <- Availability.validate_inputs(meeting_type, resources, rules),
         :ok <- Assignment.validate(resources, opts) do
      case Policy.notice_ok(existing, meeting_type.reschedule_policy, opts[:now]) do
        :ok ->
          decision(request, meeting_type, {resources, rules}, opts, {existing, request.slot})

        {:error, reason} ->
          {:ok,
           %Decision{
             status: :policy_reject,
             slot: request.slot,
             meeting_type_id: meeting_type.id,
             reasons: [{:policy, :reschedule, reason}]
           }}
      end
    end
  end

  @doc """
  Pure cancellation-policy check for an existing booking against `:now`.
  Refund and fee semantics are consumer concerns layered on the result.

  ## Example

      iex> existing =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...> ExBooking.evaluate_cancellation(existing, meeting_type, now: ~U[2026-07-13 08:00:00Z])
      {:ok, %{allowed?: true, reason: nil}}

  """
  @spec evaluate_cancellation(Interval.t(), MeetingType.t(), keyword()) ::
          {:ok, %{allowed?: boolean(), reason: atom() | nil}} | {:error, term()}
  def evaluate_cancellation(existing, %MeetingType{} = meeting_type, opts) do
    with {:ok, opts} <- validate_opts(opts, @now_opts),
         :ok <- validate_existing(existing),
         :ok <- Availability.validate_meeting_type(meeting_type) do
      result =
        case Policy.notice_ok(existing, meeting_type.cancellation_policy, opts[:now]) do
          :ok -> %{allowed?: true, reason: nil}
          {:error, reason} -> %{allowed?: false, reason: reason}
        end

      {:ok, result}
    end
  end

  @doc """
  Computes the pure cancellation transition for an existing booking.

  When cancellation policy allows the action, the returned decision emits
  `:booking_canceled`, requests calendar cancellation, optionally releases an
  existing hold, and leaves persistence/publishing to the consumer.

  ## Example

      iex> existing =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...>
      ...> {:ok, decision} =
      ...>   ExBooking.cancel(existing, meeting_type, now: ~U[2026-07-13 08:00:00Z])
      ...>
      ...> hd(decision.events).type
      :booking_canceled

  """
  @spec cancel(Interval.t(), MeetingType.t(), keyword()) :: {:ok, Decision.t()} | {:error, term()}
  def cancel(existing, %MeetingType{} = meeting_type, opts) do
    with {:ok, opts} <- validate_opts(opts, @cancel_opts),
         :ok <- validate_existing(existing),
         :ok <- Availability.validate_meeting_type(meeting_type) do
      case Policy.notice_ok(existing, meeting_type.cancellation_policy, opts[:now]) do
        :ok ->
          {:ok, cancel_decision(existing, meeting_type, opts)}

        {:error, reason} ->
          {:ok, policy_reject(existing, meeting_type.id, [{:policy, :cancellation, reason}])}
      end
    end
  end

  @doc """
  Computes the pure expiry transition for a consumer-supplied hold.

  Consumers decide when a hold is expired by comparing `expires_at` with their
  own clock. This helper only returns the canonical event and release intent.

  ## Example

      iex> slot =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> hold = %ExBooking.Hold{
      ...>   id: "hold_1",
      ...>   slot: slot,
      ...>   resource_ids: ["resource_1"],
      ...>   meeting_type_id: "intro",
      ...>   expires_at: ~U[2026-07-13 08:55:00Z]
      ...> }
      ...>
      ...> {:ok, decision} = ExBooking.expire_hold(hold, [])
      ...> [{:release, "hold_1"}, {:emit, event}] = decision.intents
      ...> event.type
      :booking_expired

  """
  @spec expire_hold(Hold.t(), keyword()) :: {:ok, Decision.t()} | {:error, term()}
  def expire_hold(%Hold{} = hold, opts) do
    with {:ok, opts} <- validate_opts(opts, @routing_context_opts),
         :ok <- validate_hold_shape(hold) do
      event = %Event{
        type: :booking_expired,
        slot: hold.slot,
        resource_ids: hold.resource_ids,
        meeting_type_id: hold.meeting_type_id,
        routing_context: opts[:routing_context],
        data: %{hold_id: hold.id, expires_at: hold.expires_at}
      }

      {:ok,
       %Decision{
         status: :ok,
         slot: hold.slot,
         meeting_type_id: hold.meeting_type_id,
         resource_ids: hold.resource_ids,
         events: [event],
         intents: [{:release, hold.id}, {:emit, event}]
       }}
    end
  end

  @doc """
  Computes the pure no-show transition for an existing booking.

  No-show detection, fees, and notifications are consumer concerns. The kernel
  returns the canonical event so analytics and billing layers can consume a
  stable vocabulary.

  ## Example

      iex> existing =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> meeting_type = %ExBooking.MeetingType{id: "intro", duration_min: 30}
      ...> {:ok, decision} = ExBooking.mark_no_show(existing, meeting_type, [])
      ...> hd(decision.events).type
      :booking_no_show

  """
  @spec mark_no_show(Interval.t(), MeetingType.t(), keyword()) ::
          {:ok, Decision.t()} | {:error, term()}
  def mark_no_show(existing, %MeetingType{} = meeting_type, opts) do
    with {:ok, opts} <- validate_opts(opts, @transition_opts),
         :ok <- validate_existing(existing),
         :ok <- Availability.validate_meeting_type(meeting_type) do
      event = transition_event(:booking_no_show, existing, meeting_type, opts)
      {:ok, transition_decision(existing, opts[:resource_ids], event, [{:emit, event}])}
    end
  end

  @doc """
  Standalone assignment over pre-filtered free resources, for consumers that
  run their own availability search. See `ExBooking.Assignment`.

  ## Example

      iex> slot =
      ...>   ExBooking.Interval.new!(
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     ~U[2026-07-13 09:30:00Z]
      ...>   )
      ...>
      ...> resources = [
      ...>   %ExBooking.Resource{id: "b", timezone: "Etc/UTC"},
      ...>   %ExBooking.Resource{id: "a", timezone: "Etc/UTC"}
      ...> ]
      ...>
      ...> {:ok, [winner]} = ExBooking.assign(resources, slot, [])
      ...> winner.id
      "a"

  """
  @spec assign([Resource.t()], Interval.t(), keyword()) ::
          {:ok, [Resource.t()]}
          | {:error, :no_eligible_resource | {:invalid, atom(), term()}}
  defdelegate assign(resources, slot, opts), to: Assignment

  @doc """
  Expands a supported RFC 5545 RRULE subset into UTC intervals over a caller
  supplied horizon.

  Supported rule parts are documented in `ExBooking.RRule`.

  ## Example

      iex> {:ok, [first]} =
      ...>   ExBooking.expand_rrule(
      ...>     "FREQ=DAILY;COUNT=1",
      ...>     ~U[2026-07-13 09:00:00Z],
      ...>     30,
      ...>     from: ~U[2026-07-13 00:00:00Z],
      ...>     until: ~U[2026-07-14 00:00:00Z]
      ...>   )
      ...>
      ...> first.start_at
      ~U[2026-07-13 09:00:00Z]

  """
  @spec expand_rrule(String.t() | RRule.t(), DateTime.t(), pos_integer(), keyword()) ::
          {:ok, [Interval.t()]} | {:error, term()}
  def expand_rrule(rrule, %DateTime{} = dtstart, duration_min, opts) do
    with :ok <- validate_horizon(opts, :required),
         {:ok, opts} <- validate_opts(opts, @rrule_opts) do
      RRule.expand(rrule, dtstart, duration_min, opts[:from], opts[:until])
    end
  end

  @doc """
  Normalizes iCalendar `FREEBUSY` periods into busy intervals.

  This is a pure parser over caller-supplied iCalendar text. It performs no file
  or network I/O.

  ## Example

      iex> {:ok, [busy]} =
      ...>   ExBooking.import_ics_free_busy("FREEBUSY:20260713T090000Z/20260713T093000Z")
      ...>
      ...> busy.kind
      :busy

  """
  @spec import_ics_free_busy(String.t()) :: {:ok, [Interval.t()]} | {:error, term()}
  defdelegate import_ics_free_busy(ics), to: ICalendar, as: :free_busy

  @doc """
  Normalizes a decoded JSCalendar `Event` or `Group` into busy intervals.

  This is a pure mapper over caller-supplied maps. JSON decoding and recurrence
  expansion remain consumer concerns.

  ## Example

      iex> {:ok, [busy]} =
      ...>   ExBooking.import_jscalendar_busy(%{
      ...>     "@type" => "Event",
      ...>     "start" => "2026-07-13T09:00:00",
      ...>     "timeZone" => "Etc/UTC",
      ...>     "duration" => "PT30M"
      ...>   })
      ...>
      ...> busy.kind
      :busy

  """
  @spec import_jscalendar_busy(map()) :: {:ok, [Interval.t()]} | {:error, term()}
  defdelegate import_jscalendar_busy(object), to: JSCalendar, as: :busy_intervals

  defp decision(request, meeting_type, {resources, rules}, opts, reschedule) do
    case Availability.eligible(request, meeting_type, resources, rules, opts[:now]) do
      {:ok, free} ->
        assign_decision(request, meeting_type, free, opts, reschedule)

      {:error, {:invalid, _, _} = reason} ->
        {:error, reason}

      {:error, reasons} ->
        {:ok, rejected_decision(request, reasons, meeting_type, {resources, rules}, opts)}
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
        {:ok,
         rejected_decision(
           request,
           [{:no_eligible_resource, request.slot}],
           meeting_type,
           {free, []},
           opts
         )}

      {:error, {:invalid, _, _} = reason} ->
        {:error, reason}
    end
  end

  defp success_decision(request, meeting_type, winners, opts, reschedule) do
    resource_ids = Enum.map(winners, & &1.id)
    seat_allocations = seat_allocations(winners, meeting_type)

    with :ok <- validate_hold(opts[:hold], request, meeting_type, resource_ids, reschedule) do
      event = %Event{
        type: event_type(opts, reschedule),
        slot: request.slot,
        resource_ids: resource_ids,
        meeting_type_id: meeting_type.id,
        routing_context: request.routing_context,
        data: event_data(reschedule)
      }

      {:ok,
       %Decision{
         status: :ok,
         slot: request.slot,
         meeting_type_id: meeting_type.id,
         resource_ids: resource_ids,
         seat_allocations: seat_allocations,
         events: [event],
         intents: intents(event, opts, reschedule, resource_ids, meeting_type)
       }}
    end
  end

  defp validate_hold(_, _, _, _, {_, _}), do: :ok
  defp validate_hold(nil, _, _, _, nil), do: :ok

  defp validate_hold(
         %Hold{} = hold,
         %Request{} = request,
         %MeetingType{} = meeting_type,
         resource_ids,
         nil
       ) do
    with :ok <- validate_hold_shape(hold),
         true <- hold.meeting_type_id == meeting_type.id,
         true <- hold.resource_ids == resource_ids,
         true <- same_interval?(hold.slot, request.slot) do
      :ok
    else
      false -> hold_mismatch(hold, request, meeting_type, resource_ids)
      {:error, _} = error -> error
    end
  end

  defp validate_hold_shape(%Hold{id: id}) when not is_binary(id) or id == "",
    do: {:error, {:invalid, :hold, {:invalid, :id}}}

  defp validate_hold_shape(%Hold{} = hold) do
    with :ok <- validate_hold_interval(hold.slot),
         :ok <- validate_hold_resource_ids(hold.resource_ids),
         :ok <- validate_hold_meeting_type_id(hold.meeting_type_id) do
      validate_hold_expiry(hold.expires_at)
    end
  end

  defp validate_hold_interval(slot) do
    case Interval.validate(slot) do
      :ok ->
        :ok

      {:error, {:invalid, :interval, detail}} ->
        {:error, {:invalid, :hold, {:invalid, :slot, detail}}}
    end
  end

  defp validate_hold_resource_ids(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: {:error, {:invalid, :hold, {:invalid, :resource_ids}}}
  end

  defp validate_hold_resource_ids(_),
    do: {:error, {:invalid, :hold, {:invalid, :resource_ids}}}

  defp validate_hold_meeting_type_id(id) when is_binary(id) and id != "", do: :ok

  defp validate_hold_meeting_type_id(_),
    do: {:error, {:invalid, :hold, {:invalid, :meeting_type_id}}}

  defp validate_hold_expiry(%DateTime{}), do: :ok
  defp validate_hold_expiry(_), do: {:error, {:invalid, :hold, {:invalid, :expires_at}}}

  defp hold_mismatch(hold, request, meeting_type, resource_ids) do
    cond do
      hold.meeting_type_id != meeting_type.id ->
        {:error, {:invalid, :hold, {:mismatch, :meeting_type_id}}}

      hold.resource_ids != resource_ids ->
        {:error, {:invalid, :hold, {:mismatch, :resource_ids}}}

      not same_interval?(hold.slot, request.slot) ->
        {:error, {:invalid, :hold, {:mismatch, :slot}}}
    end
  end

  defp event_type(_, {_, _}), do: :booking_rescheduled
  defp event_type(opts, nil), do: if(opts[:hold], do: :booking_reserved, else: :booking_confirmed)

  defp event_data(nil), do: %{}
  defp event_data({existing, new}), do: %{from: existing, to: new}

  defp intents(event, opts, nil, resource_ids, meeting_type) do
    case opts[:hold] do
      %Hold{} = hold ->
        [{:reserve, hold}, {:emit, event}]

      nil ->
        payload = calendar_payload(event, resource_ids, meeting_type)

        [
          {:calendar_event, :create, payload},
          {:notify, :booking_confirmation, payload},
          {:emit, event}
        ]
    end
  end

  defp intents(event, opts, {_, _}, resource_ids, meeting_type) do
    release =
      case opts[:release_hold_id] do
        nil -> []
        hold_id -> [{:release, hold_id}]
      end

    payload = calendar_payload(event, resource_ids, meeting_type)

    release ++
      [
        {:calendar_event, :move, payload},
        {:notify, :booking_rescheduled, payload},
        {:emit, event}
      ]
  end

  defp calendar_payload(event, resource_ids, meeting_type) do
    %{slot: event.slot, resource_ids: resource_ids, meeting_type_id: meeting_type.id}
  end

  defp rejected_decision(request, reasons, meeting_type, {resources, rules}, opts) do
    %Decision{
      status: rejection_status(reasons),
      slot: request.slot,
      meeting_type_id: meeting_type.id,
      reasons: reasons,
      alternatives: alternatives(request, meeting_type, resources, rules, opts)
    }
  end

  defp rejection_status(reasons) do
    cond do
      Enum.any?(reasons, &match?({:no_eligible_resource, _}, &1)) -> :needs_routing
      Enum.any?(reasons, &match?({:conflict, _, _}, &1)) -> :conflict
      true -> :policy_reject
    end
  end

  defp seat_allocations(_, %MeetingType{participants: participants}) when participants != :pool,
    do: []

  defp seat_allocations(winners, %MeetingType{capacity_required: required}) do
    {allocations, _} =
      Enum.reduce(winners, {[], required}, fn resource, {allocations, remaining} ->
        consumed = min(resource.capacity, remaining)

        allocation = %{resource_id: resource.id, capacity_consumed: consumed}
        {[allocation | allocations], remaining - consumed}
      end)

    Enum.reverse(allocations)
  end

  defp alternatives(
         %Request{slot: %Interval{} = requested},
         meeting_type,
         resources,
         rules,
         opts
       ) do
    with true <- opts[:alternatives_limit] > 0,
         %DateTime{} <- opts[:from],
         %DateTime{} <- opts[:until],
         {:ok, slots} <- Availability.assemble(meeting_type, resources, rules, opts) do
      slots
      |> Enum.reject(&same_interval?(&1, requested))
      |> Enum.sort_by(&alternative_key(&1, requested))
      |> Enum.take(opts[:alternatives_limit])
    else
      _ -> []
    end
  end

  defp alternatives(_, _, _, _, _), do: []

  defp same_interval?(%Interval{} = a, %Interval{} = b),
    do: a.start_at == b.start_at and a.end_at == b.end_at

  defp same_interval?(_, _), do: false

  defp validate_existing(existing) do
    case Interval.validate(existing) do
      :ok ->
        :ok

      {:error, {:invalid, :interval, detail}} ->
        {:error, {:invalid, :existing, detail}}
    end
  end

  defp alternative_key(slot, requested) do
    distance = abs(DateTime.diff(slot.start_at, requested.start_at, :second))
    {distance, DateTime.to_unix(slot.start_at, :microsecond)}
  end

  defp cancel_decision(existing, meeting_type, opts) do
    event = transition_event(:booking_canceled, existing, meeting_type, opts)

    release =
      case opts[:release_hold_id] do
        nil -> []
        hold_id -> [{:release, hold_id}]
      end

    payload = calendar_payload(event, opts[:resource_ids], meeting_type)

    intents =
      release ++
        [
          {:calendar_event, :cancel, payload},
          {:notify, :booking_canceled, payload},
          {:emit, event}
        ]

    transition_decision(existing, opts[:resource_ids], event, intents)
  end

  defp transition_event(type, slot, meeting_type, opts) do
    %Event{
      type: type,
      slot: slot,
      resource_ids: opts[:resource_ids],
      meeting_type_id: meeting_type.id,
      routing_context: opts[:routing_context]
    }
  end

  defp transition_decision(slot, resource_ids, event, intents) do
    %Decision{
      status: :ok,
      slot: slot,
      meeting_type_id: event.meeting_type_id,
      resource_ids: resource_ids,
      events: [event],
      intents: intents
    }
  end

  defp policy_reject(slot, meeting_type_id, reasons) do
    %Decision{
      status: :policy_reject,
      slot: slot,
      meeting_type_id: meeting_type_id,
      reasons: reasons
    }
  end

  defp validate_opts(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, error} -> {:error, {:invalid, :opts, Exception.message(error)}}
    end
  end

  defp validate_horizon(opts, requirement) when is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_keyword_horizon(opts, requirement)
    else
      {:error, {:invalid, :opts, :not_a_keyword_list}}
    end
  end

  defp validate_horizon(_, _), do: {:error, {:invalid, :opts, :not_a_keyword_list}}

  defp validate_keyword_horizon(opts, requirement) do
    from? = Keyword.has_key?(opts, :from)
    until? = Keyword.has_key?(opts, :until)

    case {from?, until?, Keyword.get(opts, :from), Keyword.get(opts, :until), requirement} do
      {false, false, _, _, :optional} ->
        :ok

      {true, true, %DateTime{} = from, %DateTime{} = until, _} ->
        if DateTime.compare(from, until) == :lt,
          do: :ok,
          else: {:error, {:invalid, :horizon, :not_increasing}}

      {true, true, _, _, _} ->
        :ok

      _ ->
        {:error, {:invalid, :horizon, :requires_from_and_until}}
    end
  end
end
