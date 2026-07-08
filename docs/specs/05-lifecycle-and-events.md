# Spec 05 — Lifecycle and Events

**Status:** normative

The kernel computes lifecycle *transitions* as pure functions; the consumer owns
the state machine, persistence, and execution. The reference aggregate states
(maintained in the consumer, e.g. host application):

```text
draft → offered → held → confirmed
held → expired
confirmed → rescheduled | canceled | no_show
pending_payment → confirmed | expired
```

## Kernel lifecycle functions

- `decide/5` — produces the `held`/`confirmed` intent set for a valid request.
- `reschedule/6` — validates policy (`reschedule_policy.min_notice_min` against
  `:now` and the existing slot), releases the old slot's busy claim in its own
  computation, and re-runs decision for the new slot.
- `evaluate_cancellation/3` — pure policy answer `%{allowed?: _, reason: _}`.
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
and publishes. Names are the cross-repo contract (host application, packs, Rivure billing):

| Event `type` | Emitted when |
|---|---|
| `:booking_reserved` | A hold decision is produced |
| `:booking_confirmed` | A confirm decision is produced |
| `:booking_rescheduled` | A reschedule decision is produced (carries old + new slot in `data`) |
| `:booking_canceled` | Consumer-executed cancellation (kernel supplies template via `evaluate_cancellation` flow) |
| `:booking_expired` | Consumer expires a hold (template shape defined here for consistency) |
| `:booking_no_show` | Consumer marks no-show |

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
