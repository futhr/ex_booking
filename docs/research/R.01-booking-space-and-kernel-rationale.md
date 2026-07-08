---
ex_booking:
  id: "R.01"
  topic: "The booking space and why a pure kernel"
  category: research
  status: complete
  created: "2026-07-08"
  updated: "2026-07-08"
  decision: adopted
  tags:
    [
      "market-analysis",
      "scheduling",
      "kernel-rationale",
      "standards",
      "elixir-ecosystem"
    ]
---

# R.01 — The booking space and why a pure kernel

**Sources:** consolidation of four deep-research passes over the commercial
scheduling market (general-purpose schedulers, CRM-native meeting products,
calendar-suite booking pages, service-commerce schedulers, and revenue-routing
platforms), the open-source scheduling landscape across ecosystems, the calendaring
standards track (RFC 5545, RFC 8984), and the Elixir/Hex ecosystem, verified
against Hex.pm release data as of 2026-07-08.

This document records *why* `ex_booking` exists and the design calls carried into
the specification (`docs/specs/`). It is background, not normative. It deliberately
names no commercial product and no host application: the analysis is about the
*shape* of the market, which is stable across vendors.

## 1. Bottom line

The scheduling market is no longer a "calendar link" market. Every serious platform
converges on the same layered stack:

1. **Slot math** — availability, buffers, notice, booking windows, timezone/DST
   correctness, conflict detection.
2. **Assignment** — one-on-one, collective, group capacity, round-robin (plain,
   weighted, least-recently-booked), owner-first with fallback.
3. **Qualification / routing** — forms, enrichment, CRM ownership lookup, territory
   logic, spam screening.
4. **Workflow automation** — reminders, reconfirmation, no-show handling,
   follow-ups.
5. **System sync** — CRM logging, campaign attribution propagated into booking
   records and webhooks, analytics, payments, billing.

Layers 1–2 are the kernel. Layer 3 enters the kernel only as an opaque
scoring/policy hook. Layers 3–5 belong to the consuming orchestration layer and its
recipe/adapter ecosystem. The market's own structural moves prove the boundary:
the highest-profile open-core scheduler split precisely along this line in 2026,
keeping the scheduling engine and booking infrastructure open while moving routing
forms, workflows, teams, and analytics into its commercial product.

**Decision: build a new pure kernel in Elixir. Do not port an existing product.
Reuse narrow temporal primitives only.**

## 2. What the market proved

- **General-purpose schedulers** expose event types (one-on-one, group, collective,
  round-robin), routing forms with CRM owner lookup, workflow automation, embeds,
  payments, and scheduling APIs now explicitly positioned for AI agents. Campaign
  parameters (UTM) are propagated into invitee records and webhook payloads —
  booking is treated as a *revenue-attribution event*, not a calendar event.
- **CRM-native meeting products** run scheduling inside the system of record:
  round-robin with contact-owner prioritization, "all available" group logic versus
  "one available" round-robin logic, weighted rotations, automatic interaction
  logging, and documented edge cases when a host calendar disconnects.
- **Revenue-routing platforms** (the enterprise ceiling) sell qualification,
  enrichment, multi-round-robin, distribution credits, ownership fallback,
  territories, skills, scheduling policies, and routing graphs. None of this is
  calendar math; all of it consumes calendar math.
- **Calendar-suite booking pages** (the feature floor) offer booking pages,
  calendars-to-check, buffers, daily caps, and payments delegated to a processor.
  Instructive pattern: the booking engine decides eligibility; money movement is
  delegated.
- **Recurring data model** — across every platform studied the same entities
  repeat: Host, MeetingType/EventType, AvailabilityRule, BusyInterval,
  BookingRequest, Booking/Meeting, Invitee, RoutingContext, WorkflowTrigger,
  PaymentState. The kernel models the first six; the rest are consumer concerns.

## 3. Standards

- **RFC 5545 (iCalendar)** remains the interop baseline: recurrence sets are
  defined by `DTSTART`/`RRULE`/`RDATE`/`EXDATE`, and its recurrence semantics —
  ambiguities included — are what every mature recurrence library implements.
  Do not invent recurrence syntax; align with RFC 5545 when recurrence lands.
- **RFC 8984 (JSCalendar)** is the JSON successor format, designed to remove
  iCalendar's recurrence ambiguities; a JSCalendar 2.0 revision is in IETF draft
  as of mid-2026. Any future serialization/interop surface should target
  JSCalendar alongside ICS rather than inventing a JSON shape.
- **CalDAV (RFC 4791)** and provider free/busy APIs are adapter-layer concerns;
  the kernel only ever sees normalized busy intervals.

## 4. Elixir/Hex ecosystem verdict

Best-in-class **temporal primitives**, no **booking kernel**. Release data is from
Hex.pm (2026-07-08) as context only; the verdicts below rest on each library's
documented protocol coverage and implementation fit — a library that stopped
releasing may simply be finished, so recency is never the criterion:

| Package | Latest release | Verdict for ex_booking |
|---|---|---|
| `tz` | 0.28.2 · 2026-05 | **Adopted.** Native `DateTime` + `tz` for all timezone math; no heavyweight date-time framework. (Timezone databases do need current data — here recency *is* part of correctness.) |
| `ical` | 2.0.2 · 2026-05 | **Primary candidate** for the v0.4 spike: RFC 5545-compliant parsing/serialization/recurrence, timezone handling designed around `tz`/`time_zone_info`, retains unknown `X-*` properties. Gaps to verify in the spike: BY\* rule coverage is not fully enumerated in its docs; `VFREEBUSY` is listed as future work. |
| `rrule` | 0.7.0 · 2025-04 | Second candidate: wraps the `rust-rrule` crate, a strictly validated RFC 5545 RRULE implementation. Cost: a Rust toolchain in the build (no documented precompiled NIFs) — weigh against expansion speed. |
| `cocktail` | 0.10.3 · 2024-01 | **Disqualified on protocol alignment**, not age: its own README documents unresolved DST bugs with zoned datetimes, incomplete RRULE options, no `WKST`, no `EXRULE`. DST correctness is this kernel's defining property, so those documented gaps rule it out. Useful as an Elixir-native design reference. |
| `calendar_recurrence` | 0.2.0 · 2025-11 | Deliberately minimal recurrence scope; reference only. |
| `caldav_client` | 2.0.0 · 2022-03 | CalDAV (RFC 4791) is a stable protocol, so the 2022 release is not a mark against it — evaluate its protocol coverage when calendar adapters are built; adapters are out of kernel scope regardless. |
| `tempus`, `calendar_interval`, `interval` | — | Prior art for interval reasoning; ex_booking implements its own small algebra (Allen-style relations reduced to what booking needs) to stay dependency-thin. |
| job schedulers (`oban`, `sched_ex`, …) | — | Queueing/scheduling of *work*, not of *meetings*; consumer layer. |
| LiveView calendar/UI component libraries | — | Presentation layer; consumer concern. |
| `ash` | — | Compelling for the *application model around* the kernel. If wanted, a separate wrapper package — never a kernel dependency. |

No Hex package provides availability assembly + slotting + assignment + booking
policy as a pure library. That gap is the opportunity.

## 5. The closest OSS reference, and why it is not the base

The most relevant open-source codebase in this space is a mature, self-hostable
Elixir/Phoenix scheduling application, licensed **AGPL-3.0-or-later** with a
separately protected trademark. It is *not* sloppy work: thousands of commits,
custom static-analysis rules enforcing architectural boundaries, careful DST
handling, and conflict-checked booking writes with side effects pushed outside DB
transactions.

It is still the wrong base:

- **Shape** — an integrated Phoenix/Ecto product with a supervision tree of
  caches, circuit breakers, and rate limiters; the opposite of a pure library.
- **Product fit** — its slot generation steps by meeting duration (a
  duration-coupled grid), and the inspected sources show no routing forms, lead
  qualification, territory logic, or owner-priority routing.
- **License** — AGPL with protected branding. **Concepts and test scenarios only;
  its code must never be copied or closely paraphrased into this MIT library.**

Patterns worth borrowing as *ideas*: DST wall-time resolution (ambiguous → first
occurrence; gap → snap forward), free/busy feed derivation, distinguishing
fast-fail slot unavailability from transport timeouts, and keeping slow external
calls outside DB transactions.

## 6. Design calls carried into the spec

1. **Pure decision engine** — no DB, no processes, no I/O, no clock, no randomness.
   Caller supplies `now`. Same inputs ⇒ same outputs, including list ordering.
2. **Facts and intents** — the kernel returns `Decision`s carrying side-effect
   *intents*; consumers execute them. Booking confirmation must never block on any
   downstream write (billing is event-driven and eventually consistent).
3. **Interval algebra, not ad-hoc date filtering** — overlap/subtract/merge/clip/
   inflate as the algorithmic foundation.
4. **Slot interval independent of duration** — a deliberate improvement over the
   duration-coupled grids observed in existing products.
5. **Assignment as pure policy** — fairness counters, owner priority, and scores
   are explicit inputs; GTM/CRM context flows through an opaque scoring hook. The
   kernel never learns CRM semantics.
6. **Recurrence deferred** — v0 ships weekly windows + date overrides + blackouts;
   full RRULE arrives via a spike (v0.4) aligned with RFC 5545, with `ical` as the
   leading candidate and JSCalendar (RFC 8984) as the target for any JSON interop.
7. **MIT license**, boring descriptive name (`ex_booking`), `ExBooking` namespace
   chosen so it can never alias-shadow a consumer's own `Booking` context.

## 7. Architecture split (consumer view)

```text
ex_booking (this library)      pure temporal + eligibility + assignment math
        │
orchestration layer            persistence, booking state machine, APIs, tenancy,
        │                      webhooks, routing forms, CRM/GTM/AI orchestration
        ├── recipe bundles     declarative business policy: routing templates,
        │                      qualification forms, brand defaults, attribution
        └── vendor adapters    calendar, CRM, conferencing, notification,
                               analytics, billing/metering integrations
```

Booking lifecycle events (`booking_reserved`, `booking_confirmed`,
`booking_canceled`, `booking_no_show`, …) form the contract that billing meters
and analytics consume. Multiple product surfaces can book through one shared
system instead of rebuilding scheduling per product. Extension specifications for
those layers live with their own codebases, not here.

## 8. Open questions

- RRULE/ICS spike (v0.4): `ical` (RFC 5545-compliant, BY\* coverage to be
  enumerated) vs `rrule` (rust-rrule wrapper, Rust toolchain cost) vs a minimal
  in-house RFC 5545 subset; JSCalendar mapping scope.
- Whether an Ash-resource wrapper package is worth building once a real consumer
  integration exists.
- Whether non-sales appointment commerce (packages, deposits, gift certificates)
  ever enters scope. Current answer: no; it changes the center of gravity toward
  reservation systems (rooms/equipment/credits/waitlists), which is a different
  library.
- Event-sourcing of the booking aggregate is a consumer decision, not a kernel
  one; the kernel only guarantees a canonical event vocabulary.
