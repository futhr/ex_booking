---
ex_booking:
  id: "SP.05"
  title: "Lifecycle and Events"
  domain: booking
  status: normative
  priority: high
  created: "2026-07-08"
  updated: "2026-07-29"
  tags: ["lifecycle", "events", "intents", "holds"]
  depends_on: ["R.01", "SP.01"]
---

# SP.05 — Lifecycle and Events

The kernel computes lifecycle *transitions* as pure functions; the consumer owns
the state machine, persistence, and execution. The reference aggregate states
(maintained in the consuming orchestration layer):

```text
draft → offered → held → confirmed
held → expired
confirmed → rescheduled | canceled | no_show
pending_payment → confirmed | expired
```

## Kernel lifecycle functions

- `decide/5` — produces the `held`/`confirmed` intent set for a valid request.
  With no `:hold` option it *confirms* (`:booking_confirmed`, intents
  `{:calendar_event, :create, _}`, `{:notify, :booking_confirmation, _}`, then
  `{:emit, _}`). With a consumer-supplied `:hold` it *reserves*
  (`:booking_reserved`, intents `{:reserve, hold}` then `{:emit, _}`) — the
  kernel never fabricates a `Hold` id or `expires_at`.
- `reschedule/6` — validates policy (`reschedule_policy.min_notice_min` against
  `:now` and the existing slot), and re-runs decision for the new slot against
  the exact availability facts supplied by the caller. The caller must exclude
  the identified booking's own holds/reservations before calling; the kernel
  never subtracts a generic interval by timestamp because that could erase an
  unrelated overlapping calendar event. It emits
  `:booking_rescheduled` (`data: %{from: old, to: new}`) with intents
  `{:calendar_event, :move, _}`, `{:notify, :booking_rescheduled, _}`, then
  `{:emit, _}`, optionally prefixed by `{:release, hold_id}` when
  `:release_hold_id` is given. A failed policy check yields
  `Decision{status: :policy_reject, reasons: [{:policy, :reschedule, _}]}`.
- `evaluate_cancellation/3` — pure policy answer `%{allowed?: _, reason: _}`.
- `cancel/3` — evaluates cancellation policy and, when allowed, emits
  `:booking_canceled` with persist-first intents (`{:release, hold_id}` when
  supplied, `{:calendar_event, :cancel, _}`,
  `{:notify, :booking_canceled, _}`, then `{:emit, _}`).
- `expire_hold/2` — pure template for consumer-driven hold expiry. It emits
  `:booking_expired` and returns `{:release, hold.id}` before `{:emit, _}`.
- `mark_no_show/3` — pure no-show transition. It emits `:booking_no_show`;
  downstream fee/notification handling is outside the kernel.
- `ExBooking.Hold` — holds are data; consumers persist them, include them as
  `kind: :hold` busy time in subsequent searches, and expire them by comparing
  `expires_at` with their clock. The kernel never expires anything itself.

Every lifecycle entry point preflights its temporal and nested inputs before
policy arithmetic or event construction. Existing/hold slots must be valid UTC
intervals, meeting ids and resource ids must be non-empty strings, hold expiry
must be a `DateTime`, and cancellation/reschedule policies must have an exact
`%{allowed: boolean(), min_notice_min: non_neg_integer()}` shape. Malformed
inputs return SP.02 tagged errors and emit no decision, event, or intent.

### Supplied hold consistency

After request validation and deterministic assignment, but before building a
reservation event or intents, `decide/5` validates a supplied hold against the
canonical result:

```text
hold.meeting_type_id == request.meeting_type_id == meeting_type.id
hold.slot.start_at == request.slot.start_at
hold.slot.end_at == request.slot.end_at
hold.resource_ids == assigned resource ids  # same deterministic order
```

The hold id must be a non-empty string and `expires_at` must be a `DateTime`.
A mismatch returns the SP.02 tagged malformed-input error and emits no decision,
event, or intent. Consumer-supplied ids and expiry instants remain opaque; the
kernel does not invent them or read the clock to decide whether the hold expired.

## Payment semantics

Payment state is data, not kernel behavior. A meeting type whose consumer requires
payment moves through `pending_payment` in the consumer's state machine; the kernel
only re-validates the slot when asked (same `validate_request/5`). Rule inherited
from market evidence (R.01): *booking confirmation never blocks on a billing
write*. Consumers publish lifecycle facts asynchronously; a product may derive a
separate contract meter from evidence, but the kernel never declares an event billable.

## Canonical events

Emitted inside `Decision.events`; the consumer stamps `occurred_at`, assigns ids,
and publishes. Names are commercially neutral lifecycle facts consumed by
orchestration and analytics and available as evidence to consumer-defined meters:

| Event `type` | Emitted when |
|---|---|
| `:booking_reserved` | A hold decision is produced |
| `:booking_confirmed` | A confirm decision is produced |
| `:booking_rescheduled` | A reschedule decision is produced (carries old + new slot in `data`) |
| `:booking_canceled` | `cancel/3` allows cancellation |
| `:booking_expired` | `expire_hold/2` is called by the consumer after its expiry check |
| `:booking_no_show` | `mark_no_show/3` is called by the consumer |

`Event.routing_context` is the untouched `Request.routing_context` — this is how
UTM/CRM attribution reaches analytics and downstream evidence projections without
the kernel knowing what it means. Its presence never makes an event billable.

## Side-effect intents

`Decision.intents` describe what the consumer must execute. v0 vocabulary:

```elixir
{:reserve, ExBooking.Hold.t()}                 # persist hold, schedule expiry
{:release, hold_id :: String.t()}              # on reschedule/cancel paths
{:calendar_event, :create | :cancel | :move, payload :: map()}
{:notify, template :: atom(), payload :: map()}   # confirmation, reminder seeds
{:emit, ExBooking.Event.t()}                   # publish commercially neutral lifecycle fact
```

Intents are ordered: consumers execute sequentially, persist-first (`:reserve`
always precedes `:calendar_event`/`:notify`/`:emit`). Idempotency keys are consumer
concerns (holds carry consumer-supplied ids for this reason).

An immediately confirmed booking emits calendar create, booking-confirmation
notification, then lifecycle event. Reschedule emits calendar move,
booking-rescheduled notification, then lifecycle event; cancellation emits
calendar cancel, booking-canceled notification, then lifecycle event. A held
reservation does not notify until confirmation. Notification payloads contain
only the normalized slot, resource ids, and meeting type id; consumers load
invitee contact data at execution time rather than persisting it in an intent.

## Snapshotting

A `Decision` embeds everything in force at decision time (slot, resources,
meeting type id, pool seat allocations, reasons). Consumers persist the
decision alongside the booking so later disputes ("why was this resource
chosen?") are answerable without replaying rules that have since changed.

## Alternatives

Rejected `decide/5` calls compute nearest valid alternatives only when the caller
supplies an explicit `:from`/`:until` horizon. Alternatives are sorted by absolute
distance from the requested slot start, then by start time for determinism, and
bounded by `:alternatives_limit` (default `3`). Without a horizon, alternatives
remain empty rather than guessing a search window.
