# Spec 00 — Overview

**Status:** normative · applies to `ex_booking` v0.x

ExBooking is a pure decision engine for sales-meeting booking. It answers:

- *What slots are valid* for a meeting type, a set of resources, and their rules?
- *Does this booking request conflict* with busy time, buffers, notice, or policy?
- *Which resource(s) should take it*, given an assignment strategy and explicit
  fairness inputs?
- *What must happen next* — as side-effect intents the consumer executes.

## Layering

```text
consumer app (e.g. host application)
  owns: persistence, state machine, APIs, auth/tenancy, jobs, webhooks,
        calendar/CRM/video/payment adapters, UI
        │  normalized structs in ──┐
        ▼                          │ decisions + intents out
              ExBooking (this library)
  owns: interval algebra, availability assembly, slot generation,
        conflict detection, assignment, lifecycle/policy evaluation
```

## Scope

| Responsibility | In kernel |
|---|---|
| Working-hour windows, date overrides, blackouts | Yes |
| Wall-time and timezone-safe slot generation (DST rules) | Yes |
| Recurring window expansion (weekly now; RRULE per roadmap) | Yes |
| Busy-interval normalization and subtraction | Yes |
| Buffers, lead time, booking window, daily caps, capacity | Yes |
| Multi-party "all free" and pooled availability math | Yes |
| Assignment strategies with explicit fairness inputs | Yes |
| Cancellation/reschedule policy evaluation | Yes |
| Hold/expiry and lifecycle transition computation | Yes |
| Side-effect intent and canonical event generation | Yes |

## Non-scope (forever)

| Responsibility | Belongs to |
|---|---|
| Persistence, Ecto schemas, migrations | consumer |
| Background jobs, retries, webhook delivery | consumer |
| OAuth, CalDAV/Google/Microsoft calendar sync | plugins |
| CRM sync, enrichment, qualification forms, GTM analytics | host apps/packs |
| Payments, billing, invoicing (Stripe, Rivure) | plugins |
| Notifications (email/SMS/Slack), UI, embeds | host application |
| Multi-tenancy, auth, RBAC | host application |
| AI features (prep, notetaking, phone agents) | host application |

## Determinism contract

1. **No ambient inputs.** Kernel code never reads the clock, environment,
   application config (beyond the compile-time timezone database), or randomness.
   `now :: DateTime.t()` is a required option on every time-relative function.
2. **Referential transparency.** Identical inputs produce identical outputs,
   including the ordering of returned lists (slots sort ascending by start;
   ties broken by resource id).
3. **No side effects.** No processes, no I/O, no telemetry emission. Effects are
   *described* as intent structs, never performed.
4. **Total over expected inputs.** Public functions return `{:ok, _} | {:error, _}`
   tagged tuples; they raise only on programmer error (bad struct shape), never on
   business conditions (no slots, conflicts, policy rejections).

These rules are enforced culturally (CONTRIBUTING/AGENTS), by review, and by the
test strategy (Spec 06). Any function that cannot satisfy them does not belong in
this library.

## Versioning

Semantic versioning against the public API defined in Spec 02. Struct fields are
part of the public API. Pre-1.0, minor versions may break; the spec documents each
break in the CHANGELOG.
