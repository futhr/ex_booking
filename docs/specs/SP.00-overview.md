---
ex_booking:
  id: "SP.00"
  title: "Kernel Scope"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["scope", "boundary", "purity", "determinism"]
  depends_on: ["R.01"]
---

# SP.00 — Kernel Scope

This spec defines what the `ex_booking` kernel is allowed to own. It is not the
repo index, code map, product architecture, or roadmap. Use `docs/README.md` for
repo navigation and `docs/tasks/booking-tasks.md` for roadmap state.

## Purpose

`ex_booking` is a pure booking decision engine. It answers deterministic
questions over immutable inputs:

- what slots are valid;
- whether a requested slot is still valid;
- which eligible resource should take the booking;
- what lifecycle event and side-effect intent the consumer should execute.

The kernel describes facts and intents. It never executes effects.

## In Scope

The kernel owns these concerns because they are reusable booking-domain logic and
can be implemented as pure functions:

- interval algebra;
- DST-safe wall-time expansion;
- availability assembly;
- slot generation;
- lead-time, booking-window, daily-cap, cancellation, and reschedule policies;
- conflict detection;
- deterministic assignment strategies;
- hold, confirm, reschedule, cancel, expiry, and no-show transition decisions;
- canonical event and intent vocabulary;
- narrow normalization helpers for caller-supplied RRULE, ICS free/busy, and
  decoded JSCalendar data.

## Out Of Scope

These concerns require product state, side effects, credentials, provider APIs,
or product-specific orchestration. They must not be implemented in this repo:

- Phoenix controllers, LiveViews, routes, embeds, or UI;
- Ash resources or application-model wrappers;
- Ecto schemas, migrations, repositories, or transactions;
- background jobs, supervisors, schedulers, retries, or webhook delivery;
- Google, Outlook, CalDAV, CRM, conferencing, notification, analytics, or payment
  provider adapters;
- auth, tenancy, RBAC, users, organizations, teams, or admin features;
- routing forms, enrichment, territory logic, spam screening, GTM attribution
  processing, analytics dashboards, or AI features;
- generic reservation-system behavior such as rooms, equipment, inventory,
  waitlists, quota credits, or check-in/out.

A consumer may store any product-specific fields in `meta`, `metadata`, or
`routing_context`. The kernel must round-trip those fields without interpreting
product semantics.

## Purity Contract

Code under `lib/` must not:

- read the wall clock;
- perform file, network, database, process, job, or telemetry I/O;
- generate randomness;
- depend on application-specific configuration;
- mutate global state.

Every time-relative function must receive `now` or an explicit horizon from the
caller. Identical inputs must produce identical outputs, including list ordering.

## Ownership Rule

If a change modifies pure booking math or decision contracts, it belongs in this
repo and must update the matching spec plus `docs/tasks/booking-tasks.md`.

If a change needs provider I/O, persistence, UI, jobs, auth, analytics, payments,
AI, or consumer-specific orchestration, it belongs outside this repo. Record only
the boundary expectation here if needed.
