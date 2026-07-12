# ExBooking Tasks

Single roadmap for `ex_booking`.

Specs explain the current code contracts. This file is the only place that tracks
planned, in-progress, or completed repo work. If a task belongs to a consumer app,
adapter package, Ash wrapper, UI, CRM/GTM layer, analytics layer, billing system,
or provider integration, do not add it here.

Legend:

```text
[x] complete
[ ] planned / not started
[~] in progress
[-] delegated / not an in-repo task
```

## Operating Rules

```text
[x] Read CLAUDE.md before changing code.
[x] Keep lib/ex_booking.ex as the public facade.
[x] Keep implementation in flat modules under lib/ex_booking/.
[x] Keep specs descriptive, not roadmap-shaped.
[x] Keep this file as the single roadmap.
[x] Update the matching SP.NN spec with behavior changes.
[x] Run mix check --no-retry before every handoff commit.
[x] Do not add runtime dependencies beyond tz and nimble_options without discussion.
```

## Quality Gates

```text
[x] mix format --check-formatted
[x] mix compile --warnings-as-errors
[x] mix credo --strict
[x] mix deps.audit
[x] mix dialyzer
[x] mix doctor
[x] mix docs
[x] mix test --cover
[x] mix check --no-retry
```

## SP.00 — Repository Overview

Spec: `docs/specs/SP.00-overview.md`

```text
[x] Document the pure-kernel boundary.
[x] Document which concerns belong outside this repo.
[x] Document the purity and determinism contract.
[x] Document the ownership rule for in-repo versus delegated work.
[x] Keep repo navigation and module maps in docs/README.md.
[x] Point roadmap ownership to docs/tasks/booking-tasks.md only.
[x] Keep external repo architecture out of normative specs.
```

## SP.01 — Public Structs

Spec: `docs/specs/SP.01-data-model.md`

```text
[x] ExBooking.Interval struct and interval metadata.
[x] ExBooking.AvailabilityRule windows, overrides, blackouts, and policy fields.
[x] ExBooking.Resource generic busy intervals, capacity reservations,
    booking-specific daily counts, fairness, and metadata.
[x] ExBooking.Reservation explicit interval and capacity consumption.
[x] ExBooking.MeetingType duration, grid step, buffers, participants, policies.
[x] Validate availability-facing meeting fields and resource capacities/timezones
    before temporal or capacity work.
[x] ExBooking.Request slot, preferred resources, routing context, metadata.
[x] ExBooking.Decision status, alternatives, reasons, events, intents.
[x] ExBooking.Hold consumer-supplied temporary reservation data.
[x] ExBooking.Event canonical lifecycle event payload.
```

## SP.02 — Public Facade API

Spec: `docs/specs/SP.02-public-api.md`
File: `lib/ex_booking.ex`

```text
[x] available_slots/4 validates options and delegates to Availability.assemble/4.
[x] validate_request/5 validates one requested slot and returns all reasons.
[x] decide/5 validates, assigns, emits events/intents, and returns alternatives.
[x] reschedule/6 releases the existing slot in computation and emits move intents.
[x] evaluate_cancellation/3 returns pure cancellation-policy facts.
[x] cancel/3 emits pure cancellation decision and intents.
[x] expire_hold/2 emits pure hold-expiry decision and release intent.
[x] mark_no_show/3 emits pure no-show decision.
[x] assign/3 delegates standalone deterministic assignment.
[x] expand_rrule/4 delegates RRULE subset expansion.
[x] import_ics_free_busy/1 delegates ICS FREEBUSY normalization.
[x] import_jscalendar_busy/1 delegates decoded JSCalendar busy mapping.
[x] Unknown options are rejected with stable malformed-input errors.
[x] Validate request meeting-type identity, exact slot duration, and horizon
    shape before decision work; return SP.02 tagged errors without raising.
[x] Preflight availability inputs with stable errors before assignment,
    timezone conversion, arithmetic, or slot generation.
```

## SP.03 — Temporal Availability Algorithms

Spec: `docs/specs/SP.03-algorithms.md`
Files: `interval.ex`, `schedule.ex`, `slotting.ex`, `availability.ex`, `policy.ex`

```text
[x] Interval.new/3 and new!/3 validate half-open intervals.
[x] Interval.overlaps?/2, contains?/2, subtract/2, subtract_all/2.
[x] Interval.merge/1, clip/2, inflate/3, duration_min/1.
[x] Schedule.expand/3 resolves DST ambiguity to first occurrence.
[x] Schedule.expand/3 snaps spring-forward gaps forward.
[x] Schedule.expand/3 handles cross-midnight windows.
[x] Schedule.expand/3 applies date overrides and blackouts.
[x] Schedule.expand/3 rejects invalid timezones and malformed weekly/override
    windows with stable tagged errors.
[x] Slotting.generate_slots/4 keeps slot interval independent of duration.
[x] Slotting.generate_slots/4 supports :free_start and :clock alignment.
[x] Availability.assemble/4 builds deterministic available slots.
[x] Availability.eligible/5 supports :one, :collective, and :pool.
[x] Availability.validate/5 returns all policy/conflict reasons.
[x] Policy.violations/4 covers lead time, booking window, and daily cap.
[x] Policy.notice_ok/3 covers cancellation/reschedule notice rules.
[x] Require requested slots to be wholly contained in expanded rule
    offerability, including overrides and blackout subtraction.
```

## SP.04 — Assignment

Spec: `docs/specs/SP.04-assignment.md`
File: `lib/ex_booking/assignment.ex`

```text
[x] :first_available strategy.
[x] :round_robin strategy.
[x] :least_recently_booked strategy.
[x] :weighted strategy.
[x] :priority strategy.
[x] :owner_first strategy with fallback.
[x] Opaque scorer ranks before strategy key.
[x] Routing context is passed to scorer and never inspected by the kernel.
[x] Final tie-break is resource id ascending.
[x] Empty eligible resource pool returns :no_eligible_resource.
[x] Reject unsupported strategy shapes/fallbacks and non-positive weighted
    strategy weights with SP.02 tagged errors before sorting or division.
[x] Validate all supplied fairness fields and convert invalid/raised scorer
    results into SP.02 tagged errors before sorting.
```

## SP.05 — Lifecycle Events And Intents

Spec: `docs/specs/SP.05-lifecycle-and-events.md`
Files: `decision.ex`, `event.ex`, `hold.ex`, `lib/ex_booking.ex`

```text
[x] Decision status vocabulary: :ok, :conflict, :policy_reject, :needs_routing.
[x] Decision reasons use stable tagged tuples.
[x] Decision alternatives are horizon-bound and deterministic.
[x] Hold is pure consumer-supplied data.
[x] Event vocabulary covers reserved, confirmed, rescheduled, canceled, expired, no_show.
[x] decide/5 emits confirmation or reservation events/intents.
[x] reschedule/6 emits reschedule events/intents.
[x] cancel/3 emits cancellation events/intents.
[x] expire_hold/2 emits expiry event and release intent.
[x] mark_no_show/3 emits no-show event.
[x] Intents are ordered persist-first.
[x] Consumers stamp event ids and occurred_at outside the kernel.
[x] Validate supplied holds against the canonical meeting type, requested slot,
    and deterministic assigned resource ids before emitting reservation output.
[x] Preflight lifecycle intervals, notice policies, and hold fields before
    policy arithmetic or event construction.
```

## SP.06 — Standards Interop Helpers

Spec: `docs/specs/SP.06-standards-interop.md`
Files: `rrule.ex`, `icalendar.ex`, `jscalendar.ex`

```text
[x] RRule supports FREQ=DAILY.
[x] RRule supports FREQ=WEEKLY.
[x] RRule supports INTERVAL, COUNT, UTC UNTIL, weekly BYDAY.
[x] RRule rejects unsupported parts explicitly.
[x] ICalendar normalizes UTC FREEBUSY start/end periods.
[x] ICalendar normalizes UTC FREEBUSY start/duration periods.
[x] ICalendar unfolds folded lines and merges busy intervals.
[x] ICalendar rejects unsupported local date-times.
[x] ICalendar treats FBTYPE=FREE as free and applies RFC 5545 defaults and
    unknown-token behavior without weakening malformed-period errors.
[x] ICalendar accepts RFC 5545 week durations and rejects invalid duration
    mixtures, empty time components, and zero durations.
[x] JSCalendar maps decoded Event objects to busy intervals.
[x] JSCalendar maps decoded Group entries to busy intervals.
[x] JSCalendar ignores free/cancelled events.
[x] JSCalendar rejects floating times and recurrence rules.
```

## SP.07 — Validation

Spec: `docs/specs/SP.07-validation.md`
Files: `test/**`, `mix.exs`, `.doctor.exs`, `.credo.exs`, `.formatter.exs`

```text
[x] Doctests cover public happy paths.
[x] Example tests cover module behavior and error vocabulary.
[x] Property tests cover interval algebra and slotting laws.
[x] DST corpus covers Europe/Stockholm and America/New_York.
[x] Determinism tests cover stable ordering and assignment tie-breaks.
[x] Coverage gate stays >= 95% excluding test/support.
[x] Doctor keeps moduledoc and public specs complete.
[x] mix check --no-retry is the final local gate.
[x] Add regression tests for request/offerability/hold validation, malformed
    strategy/horizon/weight inputs, and iCalendar FBTYPE behavior.
[x] Add facade and Schedule regressions for malformed meeting fields,
    capacities, timezones, and schedule windows.
[x] Add nested availability/resource/reservation/count/rule/request validation,
    UTC interval invariants, lifecycle-policy validation, and scorer regressions.
```

## Completed Hardening Decisions

```text
[x] Redesign reschedule release inputs so only the identified booking/resource
    claims are removed; interval equality alone must not erase unrelated busy
    time (SP.02/SP.05, breaking API work).
[x] Add capacity-consumption facts to booking reservations; overlapping interval
    count is not a sufficient capacity model (SP.01/SP.03, breaking data-model
    work).
[x] Return an explicit seat allocation for :pool decisions (SP.01/SP.04,
    breaking decision-model work).
[x] Supply booking-specific daily-count facts instead of deriving daily caps
    from every generic :busy calendar interval (SP.01/SP.03).
[x] Complete public-input hardening for temporal structs and timezones across
    availability/lifecycle entry points (SP.01/SP.02/SP.03).
[x] Validate hand-built RRULE values before stream construction, preserve zoned
    wall time across DST, and normalize recurrence output to UTC (SP.02/SP.06).
[x] Reject malformed FREEBUSY properties without a value separator
    (SP.02/SP.06).
[x] Align JSCalendar Group entries and duration/local-date-time parsing with RFC
    8984 arrays and fractional seconds; remove the invented id-keyed shape from
    the normative contract (SP.02/SP.06).
[x] Profile availability hot paths; replace Cartesian collective interval
    intersection with an equivalent linear two-pointer walk and quadratic
    rejection-reason appends with order-preserving reverse accumulation.
[x] Profile RRULE walking from distant DTSTART and retain the sequential walk:
    even a 100-year offset stayed below 35 ms, while a correct jump must retain
    absolute COUNT ordinals and DST wall-time behavior. This is not material to
    production booking horizons and is intentionally not speculative work.
```

## Delegated Outside This Repo

These are intentionally not roadmap tasks for `ex_booking`:

```text
[-] Phoenix UI, routes, controllers, LiveView, embeds.
[-] Ash resources or action wrappers.
[-] Ecto schemas, migrations, repositories, transactions.
[-] Google, Outlook, CalDAV, Zoom, Meet, Teams, Slack, email, SMS adapters.
[-] CRM/GTM enrichment, routing forms, territory logic, spam screening.
[-] Payments, refunds, packages, credits, commissions, billing meters.
[-] Analytics dashboards, GTM/GA/PostHog/Segment integrations.
[-] AI notetaking, prep, phone agents, routing agents.
```
