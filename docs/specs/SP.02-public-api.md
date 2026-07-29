---
ex_booking:
  id: "SP.02"
  title: "Public API"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-29"
  tags: ["api", "facade", "options", "error-vocabulary"]
  depends_on: ["R.01", "SP.01"]
---

# SP.02 — Public API

The facade module `ExBooking` is the primary supported entry point. The struct
modules define public data contracts. Lower-level functions documented in
SP.03, SP.04, and SP.06 are also supported for consumers that need to compose
the kernel below the facade.

## Common options

Every time-relative function takes a keyword list with:

| Option | Type | Required | Meaning |
|---|---|---|---|
| `:now` | `DateTime.t()` | yes | The caller's current time; basis for lead-time and window checks |
| `:from` | `DateTime.t()` | search functions | Horizon start |
| `:until` | `DateTime.t()` | search functions | Horizon end |
| `:strategy` | `atom() \| {atom(), keyword()}` | no | Assignment strategy (SP.04); default `:first_available` |
| `:scorer` | `(Resource.t(), map() -> number()) \| nil` | no | Opaque scoring hook receiving `routing_context` (SP.04) |
| `:hold` | `ExBooking.Hold.t() \| nil` | no (`decide/5`) | When present, `decide/5` produces a *reserve* decision (`:booking_reserved` + `{:reserve, hold}`) instead of a *confirm* decision. The kernel generates nothing — the consumer supplies the `Hold` (id, `expires_at`). |
| `:release_hold_id` | `String.t() \| nil` | no (`reschedule/6`) | When present, `reschedule/6` prepends a `{:release, hold_id}` intent for the old hold. |

Options are validated with `NimbleOptions`; unknown keys are rejected.

When a horizon is accepted, `:from` and `:until` must be supplied together as
`DateTime`s and `from < until`. An incomplete or non-increasing horizon is
malformed input. Assignment strategies must be one of the forms defined in
SP.04. Validation happens before temporal expansion, arithmetic, sorting, or
strategy dispatch; caller-controlled malformed input returns `{:error, _}` and
must not raise.

Nested caller-built data is validated with the same rule. Stable tagged errors
include `{:invalid, :interval, detail}`, meeting/request field errors,
`{:invalid, :resource_busy | :resource_reservations | :daily_booking_counts, detail}`,
`{:invalid, :resource_fairness, detail}`, rule field errors, lifecycle policy
errors, `{:invalid, :hold, detail}`, and `{:invalid, :scorer_result, detail}`.
The `detail` identifies the offending value or indexed nested field. These tags
are public vocabulary; malformed nested data never becomes a conflict or gets
silently ignored.

The nested-validation vocabulary is exactly:

```text
{:invalid, :interval, :datetime_required | :empty_or_reversed | :not_utc}
{:invalid, :meeting_type_id | :invitee_timezone | :preferred_resource_ids |
           :routing_context | :meeting_buffers | :cancellation_policy |
           :reschedule_policy, detail}
{:invalid, :resource_id, value}
{:invalid, :resource_busy | :resource_reservations | :daily_booking_counts,
           detail}
{:invalid, :resource_fairness, detail}
{:invalid, :blackouts | :lead_time_min | :booking_window_days | :max_per_day |
           :rule_buffers, detail}
{:invalid, :existing, :datetime_required | :empty_or_reversed | :not_utc}
{:invalid, :hold, detail}
{:invalid, :scorer_result, {resource_id, value | :raised}}
```

## Request invariants

`validate_request/5`, `decide/5`, and `reschedule/6` first establish these
structural invariants:

```text
request.meeting_type_id == meeting_type.id
request.slot is a valid Interval
DateTime.diff(request.slot.end_at, request.slot.start_at, :second)
  == meeting_type.duration_min * 60
```

Failure returns a tagged `{:invalid, _, _}` error. These failures are not
availability reasons and do not produce a `Decision`. A structurally valid slot
can still be rejected because it is not contained by expanded offerability or is
otherwise unavailable; those are normal decision/validation reasons (SP.03).

## Functions

```elixir
@spec available_slots(
        ExBooking.MeetingType.t(),
        [ExBooking.Resource.t()],
        [ExBooking.AvailabilityRule.t()],
        keyword()
      ) :: {:ok, [ExBooking.Interval.t()]} | {:error, term()}
```

Full availability pipeline (SP.03): expand rules → subtract busy (buffer-inflated)
→ snap to slot grid → filter lead time/window/caps → apply participant mode.
Returns slots sorted ascending by `start_at`.

Before assignment, timezone conversion, temporal arithmetic, or slot generation,
the facade validates the complete nested meeting, request, resource, reservation,
daily-count, fairness, and rule shapes. `validate_request/5`, `decide/5`, and
`reschedule/6` use the same preflight contract.

Supported options:

- `:now`, `:from`, `:until` — required `DateTime` inputs supplied by the caller.
- `:align` — optional slot-grid anchoring, `:free_start` (default) or `:clock`.

```elixir
@spec validate_request(
        ExBooking.Request.t(),
        ExBooking.MeetingType.t(),
        [ExBooking.Resource.t()],
        [ExBooking.AvailabilityRule.t()],
        keyword()
      ) ::
        :ok
        | {:error, [reason :: term()] | {:invalid, field :: atom(), detail :: term()}}
```

Checks a specific requested slot without committing to an assignment. A
well-formed request returns all availability and policy reasons, not just the
first. A structurally malformed request returns one tagged `{:invalid, _, _}`
error rather than a reason list.

Supported options:

- `:now` — required `DateTime` input supplied by the caller.
- `:from`, `:until` — optional paired horizon inputs; malformed horizon shapes
  are rejected consistently with decision entry points.
- `:strategy`, `:scorer` — validated up front so malformed assignment inputs
  cannot be hidden by current availability.

```elixir
@spec decide(
        ExBooking.Request.t(),
        ExBooking.MeetingType.t(),
        [ExBooking.Resource.t()],
        [ExBooking.AvailabilityRule.t()],
        keyword()
      ) :: {:ok, ExBooking.Decision.t()} | {:error, term()}
```

The core entry point: validate + assign + produce events/intents. A `Decision` is
returned even for rejections (`status: :conflict | :policy_reject`), including
nearest `alternatives` when `:from`/`:until` are supplied. `{:error, _}` is
reserved for malformed input.

Supported options:

- `:now` — required `DateTime` input supplied by the caller.
- `:from`, `:until` — optional alternatives horizon for rejected decisions.
- `:alternatives_limit` — optional non-negative integer, default `3`.
- `:align` — optional slot-grid anchoring for alternatives, `:free_start`
  (default) or `:clock`.
- `:strategy`, `:scorer`, `:hold` — see SP.04/SP.05.

```elixir
@spec reschedule(
        existing :: ExBooking.Interval.t(),
        ExBooking.Request.t(),
        ExBooking.MeetingType.t(),
        [ExBooking.Resource.t()],
        [ExBooking.AvailabilityRule.t()],
        keyword()
      ) :: {:ok, ExBooking.Decision.t()} | {:error, term()}
```

Like `decide/5`, but evaluates the meeting type's reschedule policy against the
existing slot and emits `:booking_rescheduled` semantics. Callers must remove
the identified booking's own holds/reservations from the supplied resource
facts. The kernel never subtracts generic busy time by interval equality.

Supported options:

- `:now` — required `DateTime` input supplied by the caller.
- `:from`, `:until`, `:alternatives_limit`, `:align` — optional rejected-decision
  alternative search controls, as in `decide/5`.
- `:strategy`, `:scorer` — see SP.04.
- `:release_hold_id` — optional old hold id released before move intents.

Options scoped to a different entry point are unknown at this boundary and are
rejected. In particular, `:hold` is accepted only by `decide/5`, while
`:release_hold_id` is accepted only by `reschedule/6` and `cancel/3`.

```elixir
@spec evaluate_cancellation(
        existing :: ExBooking.Interval.t(),
        ExBooking.MeetingType.t(),
        keyword()
      ) :: {:ok, %{allowed?: boolean(), reason: atom() | nil}}
```

Pure policy check against `cancellation_policy` and `:now`. Refund/fee semantics
are consumer concerns layered on the result.

```elixir
@spec cancel(
        existing :: ExBooking.Interval.t(),
        ExBooking.MeetingType.t(),
        keyword()
      ) :: {:ok, ExBooking.Decision.t()} | {:error, term()}
```

Computes the pure cancellation transition. When policy allows cancellation, the
decision emits `:booking_canceled`, optionally releases a hold, requests calendar
cancellation, and emits the canonical event.

Supported options:

- `:now` — required `DateTime` input supplied by the caller.
- `:resource_ids` — optional resource ids attached to the event and payload.
- `:routing_context` — optional opaque context echoed into the event.
- `:release_hold_id` — optional hold id released before calendar cancellation.

```elixir
@spec expire_hold(
        ExBooking.Hold.t(),
        keyword()
      ) :: {:ok, ExBooking.Decision.t()} | {:error, term()}
```

Computes the pure hold-expiry transition for a consumer-supplied hold. Consumers
decide *when* expiry happens; the kernel only returns `:booking_expired` and
`{:release, hold_id}`.

Supported options:

- `:routing_context` — optional opaque context echoed into the event.

```elixir
@spec mark_no_show(
        existing :: ExBooking.Interval.t(),
        ExBooking.MeetingType.t(),
        keyword()
      ) :: {:ok, ExBooking.Decision.t()} | {:error, term()}
```

Computes the pure no-show transition. Fee, notification, and revenue-policy
effects remain consumer concerns consuming the canonical event.

Supported options:

- `:resource_ids` — optional resource ids attached to the event.
- `:routing_context` — optional opaque context echoed into the event.

```elixir
@spec assign(
        [ExBooking.Resource.t()],
        ExBooking.Interval.t(),
        keyword()
      ) ::
        {:ok, [ExBooking.Resource.t()]}
        | {:error, :no_eligible_resource | {:invalid, atom(), term()}}
```

Standalone assignment (SP.04) for consumers that run their own availability
search but want kernel strategies.

```elixir
@spec expand_rrule(
        String.t() | ExBooking.RRule.t(),
        dtstart :: DateTime.t(),
        duration_min :: pos_integer(),
        keyword()
      ) :: {:ok, [ExBooking.Interval.t()]} | {:error, term()}
```

Expands the supported RFC 5545 RRULE subset over `:from`/`:until`. Supported
parts are `FREQ=DAILY`, `FREQ=WEEKLY`, `INTERVAL`, `COUNT`, `UNTIL`, and weekly
`BYDAY`. Unsupported parts fail explicitly.

```elixir
@spec import_ics_free_busy(String.t()) ::
        {:ok, [ExBooking.Interval.t()]} | {:error, term()}
```

Normalizes RFC 5545 iCalendar `FREEBUSY` periods from caller-supplied text into
UTC busy intervals. No file or network I/O is performed.

```elixir
@spec import_jscalendar_busy(map()) ::
        {:ok, [ExBooking.Interval.t()]} | {:error, term()}
```

Normalizes decoded RFC 8984 JSCalendar `Event` or `Group` maps into UTC busy
intervals. The kernel does not decode JSON, expand recurrence rules, or invent
non-standard calendar shapes.

## Error vocabulary

`{:error, _}` payloads and `Decision.reasons` entries are tagged tuples, stable
across patch versions:

```elixir
{:invalid, field :: atom(), detail :: term()}
{:conflict, resource_id :: String.t(), ExBooking.Interval.t()}
{:lead_time, minutes_short :: pos_integer()}
{:outside_window, Date.t()}
{:daily_cap, resource_id :: String.t(), Date.t()}
{:policy, :cancellation | :reschedule, :not_allowed | :min_notice}
{:no_eligible_resource, ExBooking.Interval.t()}
```

The following malformed-input details are normative for this correctness batch:

```elixir
{:invalid, :meeting_type_id, {:mismatch, request_id, meeting_type_id}}
{:invalid, :slot, :required | :invalid_interval}
{:invalid, :slot_duration, {:expected, expected_seconds, :actual, actual_seconds}}
{:invalid, :horizon, :requires_from_and_until | :not_increasing}
{:invalid, :strategy, supplied_strategy}
{:invalid, :resource_weight, {resource_id, supplied_weight}}
{:invalid, :rule_timezone, supplied_timezone}
{:invalid, :resource_timezone, {resource_id, supplied_timezone}}
{:invalid, :duration_min, supplied_duration}
{:invalid, :slot_interval_min, supplied_interval}
{:invalid, :capacity_required, supplied_capacity}
{:invalid, :participants, supplied_participants}
{:invalid, :resource_capacity, {resource_id, supplied_capacity}}
{:invalid, :windows, {:weekly, index, supplied_window}}
{:invalid, :windows, {:weekly, :not_a_list, supplied_windows}}
{:invalid, :overrides, {:entry, index, supplied_override}}
{:invalid, :overrides, {:window, override_index, window_index, supplied_window}}
{:invalid, :overrides, {:not_a_list, supplied_overrides}}
{:invalid, :hold, {:mismatch, :meeting_type_id | :slot | :resource_ids}}
{:invalid, :hold, {:invalid, :id | :expires_at}}
{:invalid, :rrule, :arguments | :interval | :count | :until | :byday}
{:invalid, :freebusy, :property}
{:invalid, :jscalendar, :entries | :start | :duration}
```

The outer `{:error, reason}` wrapper is used for these values. Implementations
may add more `{:invalid, field, detail}` cases for other malformed fields, but
must not collapse the cases above into exceptions or untagged strings.

## Stability

Anything not listed in this spec may change without notice. Additions to the
error vocabulary are minor-version changes; removals/renames are breaking.
