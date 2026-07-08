---
ex_booking:
  id: "SP.02"
  title: "Public API"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["api", "facade", "options", "error-vocabulary"]
  depends_on: ["R.01", "SP.01"]
---

# SP.02 — Public API

The facade module `ExBooking` is the supported entry point. Submodules
(`ExBooking.Interval`, `ExBooking.Slotting`) are public for consumers with
lower-level needs; everything else is internal until listed here.

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
      ) :: :ok | {:error, [reason :: term()]}
```

Checks a specific requested slot without committing to an assignment. Returns all
failing reasons, not just the first.

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
nearest `alternatives`. `{:error, _}` is reserved for malformed input.

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
existing slot, treats the existing slot's busy time as released, and emits
`:booking_rescheduled` semantics.

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
@spec assign(
        [ExBooking.Resource.t()],
        ExBooking.Interval.t(),
        keyword()
      ) :: {:ok, [ExBooking.Resource.t()]} | {:error, :no_eligible_resource}
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
:not_implemented
```

## Stability

Anything not listed in this spec may change without notice. Additions to the
error vocabulary are minor-version changes; removals/renames are breaking.
