---
ex_booking:
  id: "SP.05"
  title: "Lifecycle and Events"
  domain: booking
  status: normative
  priority: high
  created: "2026-07-08"
  updated: "2026-07-08"
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
  `{:calendar_event, :create, _}` then `{:emit, _}`). With a consumer-supplied
  `:hold` it *reserves* (`:booking_reserved`, intents `{:reserve, hold}` then
  `{:emit, _}`) — the kernel never fabricates a `Hold` id or `expires_at`.
- `reschedule/6` — validates policy (`reschedule_policy.min_notice_min` against
  `:now` and the existing slot), releases the old slot's busy claim in its own
  computation, and re-runs decision for the new slot. It emits
  `:booking_rescheduled` (`data: %{from: old, to: new}`) with intents
  `{:calendar_event, :move, _}` then `{:emit, _}`, optionally prefixed by
  `{:release, hold_id}` when `:release_hold_id` is given. A failed policy check
  yields `Decision{status: :policy_reject, reasons: [{:policy, :reschedule, _}]}`.
- `evaluate_cancellation/3` — pure policy answer `%{allowed?: _, reason: _}`.
- `cancel/3` — evaluates cancellation policy and, when allowed, emits
  `:booking_canceled` with persist-first intents (`{:release, hold_id}` when
  supplied, `{:calendar_event, :cancel, _}`, then `{:emit, _}`).
- `expire_hold/2` — pure template for consumer-driven hold expiry. It emits
  `:booking_expired` and returns `{:release, hold.id}` before `{:emit, _}`.
- `mark_no_show/3` — pure no-show transition. It emits `:booking_no_show`;
  downstream fee/notification handling is outside the kernel.
- `ExBooking.Hold` — holds are data; consumers persist them, include them as
  `kind: :hold` busy time in subsequent searches, and expire them by comparing
  `expires_at` with their clock. The kernel never expires anything itself.

## Payment semantics

Payment state is data, not kernel behavior. A meeting type whose consumer requires
payment moves through `pending_payment` in the consumer's state machine; the kernel
only re-validates the slot when asked (same `validate_request/5`). Rule inherited
from market evidence (R.01): *booking confirmation never blocks on a billing
write* — billing consumes events asynchronously.

## Canonical events

Emitted inside `Decision.events`; the consumer stamps `occurred_at`, assigns ids,
and publishes. Names are the cross-system contract consumed by orchestration,
analytics, and billing meters:

| Event `type` | Emitted when |
|---|---|
| `:booking_reserved` | A hold decision is produced |
| `:booking_confirmed` | A confirm decision is produced |
| `:booking_rescheduled` | A reschedule decision is produced (carries old + new slot in `data`) |
| `:booking_canceled` | `cancel/3` allows cancellation |
| `:booking_expired` | `expire_hold/2` is called by the consumer after its expiry check |
| `:booking_no_show` | `mark_no_show/3` is called by the consumer |

`Event.routing_context` is the untouched `Request.routing_context` — this is how
UTM/CRM attribution reaches analytics and billing without the kernel knowing what
it means.

## Side-effect intents

`Decision.intents` describe what the consumer must execute. v0 vocabulary:

```elixir
{:reserve, ExBooking.Hold.t()}                 # persist hold, schedule expiry
{:release, hold_id :: String.t()}              # on reschedule/cancel paths
{:calendar_event, :create | :cancel | :move, payload :: map()}
{:notify, template :: atom(), payload :: map()}   # confirmation, reminder seeds
{:emit, ExBooking.Event.t()}                   # publish to event bus / billing
```

Intents are ordered: consumers execute sequentially, persist-first (`:reserve`
always precedes `:calendar_event`/`:notify`/`:emit`). Idempotency keys are consumer
concerns (holds carry consumer-supplied ids for this reason).

## Snapshotting

A `Decision` embeds everything in force at decision time (slot, resources,
meeting type id, reasons). Consumers persist the decision alongside the booking so
later disputes ("why was this host chosen?") are answerable without replaying
rules that have since changed.

## Alternatives

Rejected `decide/5` calls compute nearest valid alternatives only when the caller
supplies an explicit `:from`/`:until` horizon. Alternatives are sorted by absolute
distance from the requested slot start, then by start time for determinism, and
bounded by `:alternatives_limit` (default `3`). Without a horizon, alternatives
remain empty rather than guessing a search window.
