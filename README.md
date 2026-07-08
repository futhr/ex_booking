# ExBooking

**A pure booking kernel for sales scheduling.** ExBooking answers deterministic
questions — *what slots are valid? does this request conflict? which host should
take it? what side effects must happen next?* — as pure functions over immutable
inputs. No database, no supervision tree, no HTTP, no side effects.

> Version 0.1.0. The v0.1–v0.3 kernel is implemented — availability assembly,
> DST-safe slot generation, conflict detection, assignment strategies, and the
> booking lifecycle (decide, reschedule, cancellation). The data model, public
> API, and algorithms are specified in [`docs/specs/`](docs/specs/SP.00-overview.md).
> Standards interop (RRULE/ICS/JSCalendar) is future work per the
> [roadmap](docs/specs/SP.07-roadmap.md).

## Why

Commercial scheduling platforms all converge on the same stack: a compact
scheduling core wrapped in routing, workflow, and CRM layers. The Elixir
ecosystem has excellent temporal primitives (`tz`, recurrence, ICS) but no
reusable booking-domain kernel. ExBooking is that missing layer — the core
only, deliberately small. The full rationale lives in
[`docs/research/`](docs/research/R.01-booking-space-and-kernel-rationale.md).

## Design contract

- **Deterministic** — same inputs, same outputs. The caller supplies `now`;
  the kernel never reads the clock, generates randomness, or touches I/O.
- **Facts and intents** — the kernel returns decisions and side-effect
  *intents* (create calendar event, send notification, emit billing event).
  The consuming application executes them.
- **Slot interval ≠ duration** — a 30-minute meeting can sit on a 15-minute
  grid. Slot stepping is a first-class, independent setting.
- **DST-safe** — wall-time expansion resolves ambiguous times to the first
  occurrence and snaps through spring-forward gaps.
- **Routing is a hook** — assignment strategies are pure functions over
  explicit inputs; GTM/CRM context enters through an opaque scoring hook,
  never through kernel knowledge of CRM semantics.

## What it is not

Persistence, background jobs, OAuth, calendar sync, CRM sync, payments,
notifications, UI, and multi-tenancy are all consumer concerns. See the
[scope table](docs/specs/SP.00-overview.md) for the explicit boundary.

## Quick look

```elixir
meeting_type = %ExBooking.MeetingType{
  id: "demo_30",
  duration_min: 30,
  slot_interval_min: 15
}

{:ok, slots} =
  ExBooking.available_slots(meeting_type, resources, rules,
    from: ~U[2026-07-13 00:00:00Z],
    until: ~U[2026-07-17 23:59:59Z],
    now: DateTime.utc_now()
  )

{:ok, %ExBooking.Decision{} = decision} =
  ExBooking.decide(request, meeting_type, resources, rules, now: DateTime.utc_now())

decision.events
#=> [%ExBooking.Event{type: :booking_confirmed, ...}]

decision.intents
#=> [{:calendar_event, :create, %{...}}, {:emit, %ExBooking.Event{...}}]
```

## Installation

```elixir
def deps do
  [
    {:ex_booking, "~> 0.1.0"}
  ]
end
```

ExBooking uses [`tz`](https://hex.pm/packages/tz) as its timezone database.
Configure it once in your application:

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

## Documentation

- [Research: the booking space and why a kernel](docs/research/R.01-booking-space-and-kernel-rationale.md)
- [Spec 00 — Overview, scope, determinism contract](docs/specs/SP.00-overview.md)
- [Spec 01 — Data model](docs/specs/SP.01-data-model.md)
- [Spec 02 — Public API](docs/specs/SP.02-public-api.md)
- [Spec 03 — Algorithms](docs/specs/SP.03-algorithms.md)
- [Spec 04 — Assignment strategies](docs/specs/SP.04-assignment.md)
- [Spec 05 — Lifecycle and events](docs/specs/SP.05-lifecycle-and-events.md)
- [Spec 06 — Testing strategy](docs/specs/SP.06-testing-strategy.md)
- [Spec 07 — Roadmap](docs/specs/SP.07-roadmap.md)

## License

[MIT](LICENSE)
