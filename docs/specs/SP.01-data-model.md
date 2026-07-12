---
ex_booking:
  id: "SP.01"
  title: "Data Model"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-12"
  tags: ["data-model", "structs", "public-api"]
  depends_on: ["R.01"]
---

# SP.01 — Data Model

All structs are immutable inputs/outputs. Consumers map their persistence models
into these shapes at the boundary. Struct fields are public API.

## ExBooking.Interval

A half-open interval `[start_at, end_at)` in UTC-normalized `DateTime`s.

```elixir
%ExBooking.Interval{
  start_at: DateTime.t(),      # enforced
  end_at: DateTime.t(),        # enforced; must be > start_at
  kind: atom() | nil,          # :busy | :available | :blackout | :hold | nil
  meta: map() | nil            # opaque consumer data, round-tripped untouched
}
```

Half-open semantics mean back-to-back meetings (`a.end_at == b.start_at`) do not
overlap. All algebra (SP.03) operates on this struct.

## ExBooking.AvailabilityRule

When a resource is *offerable*, before busy subtraction.

```elixir
%ExBooking.AvailabilityRule{
  timezone: String.t(),                # enforced; IANA name, e.g. "Europe/Stockholm"
  windows: [window()],                 # enforced; weekly wall-time windows
  overrides: [override()],             # date-specific replacement windows
  blackouts: [ExBooking.Interval.t()], # absolute unavailable intervals
  lead_time_min: non_neg_integer(),    # minimum notice before a slot may start
  booking_window_days: pos_integer() | nil,  # horizon; nil = unbounded
  buffers: buffers(),                  # default %{before_min: 0, after_min: 0}
  max_per_day: pos_integer() | nil     # daily booking cap; nil = uncapped
}

# window()   :: %{weekday: 1..7, start_time: Time.t(), end_time: Time.t()}
#               (ISO weekday, Monday = 1; end_time may be <= start_time to
#                express a window crossing midnight)
# override() :: %{date: Date.t(), windows: [%{start_time: Time.t(), end_time: Time.t()}]}
#               (an override with windows: [] removes the whole day)
# buffers()  :: %{before_min: non_neg_integer(), after_min: non_neg_integer()}
```

Windows and overrides are *wall time* in `timezone`; expansion to zoned intervals
follows the DST rules in SP.03.

Availability-facing APIs validate caller-built rules before expansion. The rule
timezone must resolve through the configured timezone database; `windows` and
`overrides` must be lists with the shapes above. A malformed entry is rejected
with the stable SP.02 error vocabulary rather than raising during map access or
wall-time resolution.

## ExBooking.Resource

A bookable person (or pooled seat).

```elixir
%ExBooking.Resource{
  id: String.t(),                      # enforced
  timezone: String.t(),                # enforced
  capacity: pos_integer(),             # default 1; >1 = concurrent bookings allowed
  busy: [ExBooking.Interval.t()],      # generic calendar busy; each overlap blocks all capacity
  reservations: [ExBooking.Reservation.t()], # booking-specific seat consumption
  daily_booking_counts: %{Date.t() => non_neg_integer()},
                                         # explicit counts keyed by the rule-local date
  fairness: fairness() | nil,          # explicit inputs for assignment strategies
  meta: map() | nil
}

# fairness() :: %{
#   assignments_count: non_neg_integer(),   # rolling-window assignment counter
#   last_assigned_at: DateTime.t() | nil,
#   weight: number(),                       # weighted round-robin, default 1.0
#   priority: integer()                     # higher wins in priority strategies
# }
```

The kernel never computes fairness counters from history — consumers maintain them
and pass them in, keeping the kernel stateless.

Availability-facing APIs require every resource timezone to resolve and every
resource id to be non-empty, and every capacity to be a positive integer before
availability or pool-capacity work begins. Each `busy` interval must be a valid
UTC interval; each reservation must contain a valid UTC interval and positive
capacity consumption; daily-count keys must be dates with non-negative integer
values; and supplied fairness fields must have the documented types.

Generic `busy` intervals and booking reservations are deliberately distinct.
An overlapping generic calendar interval makes the resource unavailable because
the kernel cannot infer partial capacity from an opaque calendar event. A booking
reservation carries explicit capacity consumption:

```elixir
%ExBooking.Reservation{
  interval: ExBooking.Interval.t(),
  capacity_consumed: pos_integer(),  # default 1
  meta: map() | nil
}
```

`daily_booking_counts` is likewise a caller-supplied booking fact. It is not
derived from `busy` or `reservations`: a consumer may exclude holds, canceled
bookings, imported calendar events, or other records according to its own
booking-count policy before calling the kernel. Dates use the paired
`AvailabilityRule.timezone`.

## ExBooking.MeetingType

```elixir
%ExBooking.MeetingType{
  id: String.t(),                       # enforced
  duration_min: pos_integer(),          # enforced
  slot_interval_min: pos_integer() | nil, # grid step; nil = duration_min.
                                          # INDEPENDENT of duration by design.
  buffers: buffers() | nil,             # overrides rule-level buffers
  capacity_required: pos_integer(),     # default 1; seats consumed per booking
  participants: :one | :collective | :pool, # who must be free (SP.04)
  cancellation_policy: policy() | nil,
  reschedule_policy: policy() | nil,
  meta: map() | nil
}

# policy() :: %{min_notice_min: non_neg_integer(), allowed: boolean()}
```

Channel (zoom/meet/phone), display, forms, and pricing are consumer concerns
carried in `meta` if needed.

Availability-facing APIs reject non-positive/non-integer durations, non-positive
non-`nil` slot intervals, non-positive/non-integer capacity requirements, and
participant values outside `:one | :collective | :pool` before slot generation.
They also require a non-empty id, valid buffers, and well-formed cancellation
and reschedule policies.

## ExBooking.Request

An invitee's intent, before decision.

```elixir
%ExBooking.Request{
  meeting_type_id: String.t(),          # enforced
  invitee_timezone: String.t(),         # enforced
  slot: ExBooking.Interval.t() | nil,   # the specific slot being requested
  preferred_resource_ids: [String.t()],
  routing_context: map(),               # OPAQUE. Never interpreted by the kernel;
                                        # surfaced to the scoring hook (SP.04)
                                        # and round-tripped into events.
  metadata: map() | nil
}
```

For booking validation and decisions, `meeting_type_id` must equal the supplied
`MeetingType.id`, `slot` must be present and valid, and its elapsed UTC duration
must equal `MeetingType.duration_min * 60` seconds exactly. Violations are
malformed input, not availability conflicts (SP.02).
`invitee_timezone` must resolve, preferred resource ids must be non-empty
strings, and `routing_context` must be a map. Caller-built intervals accepted
at API boundaries must already be UTC; `Interval.new/3` normalizes zoned
datetimes to UTC.

## ExBooking.Decision

The kernel's answer to booking decision and lifecycle transition functions.

```elixir
%ExBooking.Decision{
  status: :ok | :conflict | :policy_reject | :needs_routing,
  slot: ExBooking.Interval.t() | nil,
  meeting_type_id: String.t() | nil,
  resource_ids: [String.t()],
  seat_allocations: [%{resource_id: String.t(), capacity_consumed: pos_integer()}],
  alternatives: [ExBooking.Interval.t()],  # nearest valid slots when a rejected
                                           # decision has an explicit horizon
  reasons: [reason()],                     # machine-readable, e.g.
                                           # {:conflict, resource_id, interval}
                                           # {:lead_time, minutes_short}
                                           # {:outside_window, Date.t()}
  events: [ExBooking.Event.t()],           # canonical events (SP.05)
  intents: [intent()]                      # side effects for the consumer (SP.05)
}
```

`seat_allocations` is populated for accepted `:pool` decisions and is empty for
other participant modes and rejected decisions. It consumes
`MeetingType.capacity_required` seats across the deterministically ranked
resources, taking at most each resource's remaining capacity. Its sum therefore
equals `capacity_required`; a single resource may consume more than one seat.

## ExBooking.Hold

A pure representation of a temporary reservation; consumers persist and expire it.

```elixir
%ExBooking.Hold{
  id: String.t(),                    # consumer-supplied (kernel generates nothing)
  slot: ExBooking.Interval.t(),
  resource_ids: [String.t()],
  meeting_type_id: String.t(),
  expires_at: DateTime.t()
}
```

Holds appear as busy time in availability when passed in via `Resource.busy` with
`kind: :hold`.

When a hold is supplied to `decide/5`, its meeting type, temporal slot, and
ordered resource ids must match the canonical validated request and assignment
that the decision would otherwise emit (SP.05).

## ExBooking.Event

Canonical, commercially neutral vocabulary consumed by orchestration and analytics
and available as evidence to consumer-defined meters (SP.05).

```elixir
%ExBooking.Event{
  type: atom(),        # :booking_reserved | :booking_confirmed | :booking_canceled
                       # | :booking_rescheduled | :booking_expired | :booking_no_show
  slot: ExBooking.Interval.t() | nil,
  resource_ids: [String.t()],
  meeting_type_id: String.t() | nil,
  routing_context: map(),   # echoed from the Request, untouched
  data: map()               # event-specific payload
}
```

Timestamps (`occurred_at`) are stamped by the consumer at execution time — the
kernel does not read the clock.
