# ExBooking

**Deterministic booking logic for Elixir apps.**

[![Hex.pm](https://img.shields.io/hexpm/v/ex_booking.svg)](https://hex.pm/packages/ex_booking)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_booking)
[![CI](https://github.com/futhr/ex_booking/actions/workflows/ci.yml/badge.svg)](https://github.com/futhr/ex_booking/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/futhr/ex_booking.svg)](https://github.com/futhr/ex_booking/blob/main/LICENSE)

[Installation](#installation) ·
[Quick Start](#quick-start) ·
[Livebooks](#livebooks) ·
[What It Does](#what-it-does) ·
[Boundary](#boundary) ·
[Benchmarks](#benchmarks) ·
[Development](#development)

---

ExBooking is the small booking brain you put inside a product that already owns
people, calendars, CRM records, payments, and workflows. Give it normalized data;
it answers the hard deterministic questions: which slots are valid, whether a
requested time still works, which resource should take the booking, and which
events or intents the consumer app should execute next.

It has no database, no supervision tree, no provider clients, no jobs, and no
clock reads. If a decision depends on the current time, the caller passes `now`.
That makes availability, assignment, holds, cancellation, rescheduling, and
calendar-data normalization easy to test and safe to replay.

## What It Does

| Capability | Purpose |
|------------|---------|
| **Availability assembly** | Expands wall-time rules, applies overrides and blackouts, subtracts buffered busy time, and returns sorted slots. |
| **DST-safe scheduling** | Resolves ambiguous fall-back times to the first occurrence and snaps spring-forward gaps forward. |
| **Participant modes** | Supports one-resource, collective, and capacity-aware pool booking. |
| **Request validation** | Reports all conflicts and policy failures instead of stopping at the first one. |
| **Assignment** | Picks resources with deterministic first-available, round-robin, least-recently-booked, weighted, priority, owner-first, and scorer-driven strategies. |
| **Lifecycle decisions** | Emits pure events and ordered intents for confirmation, reservation, release, reschedule, cancellation, expiry, and no-show. |
| **Calendar interop** | Normalizes a narrow dependency-free RRULE, ICS FREEBUSY, and decoded JSCalendar busy-time surface. |

## Installation

```elixir
def deps do
  [
    {:ex_booking, "~> 0.1.0"}
  ]
end
```

ExBooking uses `tz` for timezone conversion. Configure it once in the consumer
application:

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

## Quick Start

```elixir
meeting_type = %ExBooking.MeetingType{
  id: "intro_call",
  duration_min: 30,
  slot_interval_min: 15
}

resource = %ExBooking.Resource{id: "resource_1", timezone: "Etc/UTC"}

rule = %ExBooking.AvailabilityRule{
  timezone: "Etc/UTC",
  windows: [
    %{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]},
    %{weekday: 2, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
  ],
  lead_time_min: 60
}

{:ok, slots} =
  ExBooking.available_slots(meeting_type, [resource], [rule],
    now: ~U[2026-07-08 12:00:00Z],
    from: ~U[2026-07-13 00:00:00Z],
    until: ~U[2026-07-14 23:59:59Z]
  )

request = %ExBooking.Request{
  meeting_type_id: "intro_call",
  invitee_timezone: "America/New_York",
  slot: hd(slots),
  routing_context: %{source: "website"}
}

{:ok, decision} =
  ExBooking.decide(request, meeting_type, [resource], [rule],
    now: ~U[2026-07-08 12:00:00Z]
  )

:ok = decision.status
[%ExBooking.Event{type: :booking_confirmed}] = decision.events
[
  {:calendar_event, :create, _payload},
  {:notify, :booking_confirmation, _payload},
  {:emit, _event}
] = decision.intents
```

## Livebooks

Six runnable notebooks in [`notebooks/`](https://github.com/futhr/ex_booking/tree/main/notebooks) teach the library from the temporal math up to lifecycle decisions.

| Notebook | Covers | Run |
|----------|--------|-----|
| [A Tour of ExBooking](notebooks/tour.livemd) | The whole library in one sitting: search, decide, holds, reschedule, cancel. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Ftour.livemd) |
| [Interval Algebra](notebooks/interval-algebra.livemd) | The half-open temporal math everything sits on. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Finterval-algebra.livemd) |
| [Schedules & DST](notebooks/schedules-and-dst.livemd) | Wall time to UTC; spring-forward gaps and fall-back folds. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Fschedules-and-dst.livemd) |
| [Availability & Slotting](notebooks/availability-and-slotting.livemd) | Duration vs. step, grid alignment, buffers, participant modes. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Favailability-and-slotting.livemd) |
| [Assignment & Policy](notebooks/assignment-and-policy.livemd) | All six strategies, fairness inputs, scorers, policy predicates. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Fassignment-and-policy.livemd) |
| [Lifecycle & Calendar Interop](notebooks/lifecycle-and-interop.livemd) | Decision anatomy, events, intents, RRULE/ICS/JSCalendar. | [Run in Livebook](https://livebook.dev/run?url=https%3A%2F%2Fex-booking.hexdocs.pm%2Flifecycle-and-interop.livemd) |

From a local checkout, `livebook server notebooks/tour.livemd` — the setup cell
detects the checkout and installs ExBooking from source, so the notebook always
demonstrates the code you have. The run links above launch the notebooks from
the latest release on [HexDocs](https://hexdocs.pm/ex_booking), where each
notebook page also carries a "Run in Livebook" badge pinned to its release.
They point at the `ex-booking.hexdocs.pm` host directly, because the
`hexdocs.pm/ex_booking` redirect drops the CORS header that Livebook needs to
render a preview.

Every code cell and its saved output is executed and verified by the test suite;
after changing library behavior, refresh the outputs with:

```bash
mix run scripts/regen_notebook_outputs.exs
```

## Boundary

ExBooking deliberately stops at decisions. Your application remains responsible
for persistence, transactions, auth, tenancy, UI, calendar sync, notifications,
CRM enrichment, routing forms, analytics, payments, retries, webhooks, and AI.

That split is the point: keep reusable booking math in one deterministic library,
and keep product-specific orchestration in the product.

## Calendar Data

The interop modules are intentionally small:

```elixir
{:ok, intervals} =
  ExBooking.expand_rrule("FREQ=WEEKLY;COUNT=4;BYDAY=MO", dtstart, 30,
    from: from,
    until: until
  )

{:ok, busy} = ExBooking.import_ics_free_busy(ics_text)
{:ok, busy} = ExBooking.import_jscalendar_busy(decoded_jscalendar_map)
```

Provider auth, transport, JSON decoding, full recurrence sync, and calendar
writeback belong outside this package.

## Benchmarks

The benchmark suite covers interval algebra, schedule expansion, availability,
validation, assignment, lifecycle decisions, and calendar-data normalizers.

```bash
mix bench --smoke   # quick run that refreshes benchmark markdown
mix bench           # full local measurement run
```

The generated benchmark report is included in HexDocs as the performance page.

## Development

```bash
mix setup
mix test
mix check --no-retry
mix docs
mix bench --smoke
```

Quality gates require formatted code, no compiler warnings, strict Credo,
Dialyzer, dependency audit, complete public documentation, generated docs, and
at least 95% test coverage.

## License

ExBooking is released under the MIT License. See [LICENSE](https://github.com/futhr/ex_booking/blob/main/LICENSE).
