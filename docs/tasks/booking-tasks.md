# ExBooking Tasks

Canonical execution checklist for `ex_booking`, the pure booking kernel. This is
the single source of truth for what is built, in progress, and planned.
`CLAUDE.md` is the contract; `docs/specs/SP.NN-*.md` are normative; this file
tracks the work that realizes them.

## Orientation (Read First)

**Purity and determinism first.** Nothing in `lib/` reads the clock, does I/O,
spawns processes, or generates randomness. `now` is always a caller input.
Identical inputs produce identical outputs, including list ordering (slots sort
ascending by `start_at`, ties by resource id).

**Spec is source of truth.** Every task cites the `SP.NN` section it realizes.
If code and spec disagree, fix the spec in the same change or surface the
mismatch — never silently diverge.

**Slot interval is independent of duration.** The grid step is
`slot_interval_min || duration_min`, never coupled to `duration_min`.

**DST is the defining property.** Wall-time expansion resolves ambiguous times
to the first occurrence and snaps through spring-forward gaps
(`SP.03` §2). Every timezone-sensitive change needs `Europe/Stockholm` +
`America/New_York` fixture coverage.

**No new dependencies** without discussion. Runtime deps are `tz` and
`nimble_options` only.

## Progress Summary

| # | Milestone | Done | Total | % | Status |
|----|-----------|-----:|------:|-----:|-------------|
| F  | Foundation and docs governance | 8 | 8 | 100% | Complete |
| M1 | v0.1 — temporal core | 7 | 7 | 100% | Complete |
| M2 | v0.2 — assignment and policy | 6 | 6 | 100% | Complete |
| M3 | v0.3 — lifecycle, events, multi-party | 7 | 7 | 100% | Complete |
| M4 | v0.4 — standards spike | 4 | 4 | 100% | Complete |
| M5 | v0.5 — research audit hardening | 3 | 3 | 100% | Complete |
| — | **Total** | **35** | **35** | **100%** | |

> M3 is complete. M3.07 is validated in the separate `host application` consumer
> repository with a documented walkthrough and integration test. M4.01 chose a
> dependency-free RRULE subset after package evaluation. M4 is complete with
> pure ICS free/busy normalization and decoded JSCalendar busy-time mapping.
> M5 closes post-build audit gaps from the base research: rejected decisions now
> return horizon-bound alternatives, and lifecycle events have pure transition
> helpers without pulling payments, providers, Ash, routing forms, analytics, or
> AI into the kernel.

## Operating Rules

- Read `CLAUDE.md` before touching code.
- Work milestones in order `F → M1 → M2 → M3 → M4`.
- Keep `lib/ex_booking.ex` a thin facade; put logic in submodules.
- Reuse the interval algebra (`ExBooking.Interval`) — do not re-derive overlap /
  subtract / merge / clip / inflate math.
- Update the relevant `SP.NN` spec in the same change as the code.

## Mandatory Gates For Every Commit

- [ ] `mix format --check-formatted`.
- [ ] `mix compile --warnings-as-errors`.
- [ ] `mix credo --strict`.
- [ ] `mix deps.audit`.
- [ ] `mix dialyzer`.
- [ ] `mix doctor` (100% moduledoc, ≥80% `@spec`).
- [ ] `mix docs`.
- [ ] `mix test --cover` (≥95%, `test/support` excluded).
- [ ] `mix check` clean.

## F — Foundation and Docs Governance

> Specs: all `SP.NN`; `R.01`.
> Exit criteria: kernel scaffold compiles; interval algebra and slotting real;
> docs governance (prefixes, frontmatter, templates, tasks, skills) in place.

- [x] F.01 Repo bootstrap: research `R.01`, full spec `SP.00`–`SP.07`, tooling
  (credo/dialyzer/doctor/ex_check/ex_doc/coveralls/stream_data), CI.
- [x] F.02 `ExBooking.Interval` algebra: `overlaps?/2`, `contains?/2`,
  `subtract/2`, `subtract_all/2`, `merge/1`, `clip/2`, `inflate/3`,
  `duration_min/1` with doctests.
- [x] F.03 `ExBooking.Slotting.generate_slots/4` + `generate_all/4` with the
  slot interval independent of duration.
- [x] F.04 Docs governance: `SP.NN` spec prefixes + `ex_booking:` YAML
  frontmatter on every spec and research note.
- [x] F.05 `docs/templates/`: `spec-base.md`, `research-base.md`, `task-base.md`.
- [x] F.06 `docs/tasks/booking-tasks.md` canonical checklist (this file).
- [x] F.07 `.claude/skills/` (done, booking-implement, booking-spec,
  booking-research, booking-review) and `.claude/standards/`.
- [x] F.08 `CLAUDE.md` canonical contract; `AGENTS.md` short pointer delegating
  to it.

## M1 — v0.1 Temporal Core

> Specs: `SP.03` (§2 DST, §3 assembly, §4 slotting, §9 conflict); `SP.02`.
> Depends on: F.
> Exit criteria: `available_slots/4` and `validate_request/5` return real
> results (no `:not_implemented`); property + DST corpus green; `mix check`
> clean; dialyzer `:no_extra_return` re-enabled default (flag removed).

- [x] M1.01 `ExBooking.Schedule.expand/3` — wall-time weekly window expansion
  over `[from, until]` with DST resolution.
  - Spec: `SP.03` §2.
  - AC: ambiguous (fall-back) resolves to the FIRST occurrence; gap
    (spring-forward) snaps FORWARD; a gap-collapsed window yields `[]`.
  - AC: cross-midnight windows (`end_time <= start_time`) expand to the next
    day; output intervals are UTC-normalized.
  - Tests: DST fixtures for `Europe/Stockholm` 2026-03-29 and
    `America/New_York` 2026-11-01; `22:00–02:00` cross-midnight case.
- [x] M1.02 Policy predicates — lead time, booking window, daily cap filters.
  - Spec: `SP.03` §3 step 8.
  - AC: lead time drops slots starting before `now + lead_time_min`; booking
    window compares rule-timezone calendar dates; daily cap counts only
    `kind: :busy` (holds excluded) on the slot's rule-tz date.
  - Tests: example tests per predicate + boundary (exactly at the cap/lead).
- [x] M1.03 `ExBooking.Availability` assembly pipeline → free intervals.
  - Spec: `SP.03` §3 (expand → override → blackout → normalize → busy inflate →
    subtract).
  - AC: buffers inflate busy (not slots) via `Interval.inflate`; overrides with
    empty windows remove the day; result merged to normal form.
  - Tests: property — free time never overlaps inflated busy; example — buffer
    blocks adjacency but not day edges.
- [x] M1.04 Facade `ExBooking.available_slots/4` (participants `:one`).
  - Spec: `SP.02`; `SP.03` §3 steps 7–10.
  - AC: pipeline feeds `Slotting.generate_all/4`; slots sorted ascending by
    `start_at`, tie-break resource id; options validated with `NimbleOptions`
    (unknown keys rejected).
  - Tests: doctest happy path; 30-min meeting on 15-min grid in 60-min window
    yields exactly three slots.
- [x] M1.05 Conflict detection + `ExBooking.validate_request/5`.
  - Spec: `SP.03` §9; `SP.02`.
  - AC: conflict iff `Interval.overlaps?(inflate(slot, before, after), busy)`;
    returns ALL failing reasons, not just the first; error vocabulary matches
    `SP.02` (`{:conflict, _, _}`, `{:lead_time, _}`, `{:outside_window, _}`,
    `{:daily_cap, _, _}`).
  - Tests: back-to-back with zero buffers is legal; buffer creates conflict;
    property — assembly-time vs validation-time buffer equivalence agree.
- [x] M1.06 Property + DST test corpus complete; ≥95% coverage held.
  - Spec: `SP.06`.
  - AC: interval algebra laws (overlaps symmetry, subtract disjointness, merge
    idempotence/normal form, clip containment); generators for rules/resources/
    meeting types (step <, ==, > duration).
  - Tests: StreamData properties + DST fixtures + determinism golden tests.
- [x] M1.07 Re-enable dialyzer `extra_return`.
  - Spec: `SP.07` v0.1.
  - AC: drop `:no_extra_return` from `mix.exs` dialyzer flags; `mix dialyzer`
    clean with real `{:ok, _}` returns.
  - Tests: `mix check` green.

## M2 — v0.2 Assignment and Policy

> Specs: `SP.04`; `SP.02`; `SP.05` (policy portions); `SP.01` `policy()`.
> Depends on: M1.
> Exit criteria: all `SP.04` strategies + scorer; `assign/3` public; `decide/5`
> for `:one`; cancellation/reschedule policy checks; benchmarks committed.

- [x] M2.01 `ExBooking.Assignment` strategies.
  - Spec: `SP.04` (strategy table + normative selection sort).
  - AC: `:first_available`, `:round_robin`, `:least_recently_booked`,
    `:weighted`, `:priority`, `:owner_first` with total, deterministic
    tie-breaks (final tie-break resource id asc); `nil last_assigned_at` ranks
    first for `:least_recently_booked`.
  - Tests: per-strategy example tests; determinism golden tests.
- [x] M2.02 Scoring hook (opaque `:scorer`).
  - Spec: `SP.04` scoring hook + selection algorithm.
  - AC: `scorer.(resource, routing_context)` ranks first (descending) before the
    strategy key; kernel never inspects `routing_context`.
  - Tests: example — scorer overrides strategy order; routing_context round-trips
    untouched.
- [x] M2.03 `ExBooking.assign/3` public.
  - Spec: `SP.02`; `SP.04` contract.
  - AC: returns one resource for `:one`, empty eligible → `{:error,
    :no_eligible_resource}`.
  - Tests: doctest; empty pool error.
- [x] M2.04 `ExBooking.decide/5` for participants `:one`.
  - Spec: `SP.02`; `SP.05`.
  - AC: validate + assign + produce `Decision` (status `:ok | :conflict |
    :policy_reject | :needs_routing`) with nearest `alternatives`; `{:error, _}`
    reserved for malformed input.
  - Tests: each `Decision.status` branch; alternatives ordering.
- [x] M2.05 Cancellation and reschedule policy evaluation in `ExBooking.Policy`.
  - Spec: `SP.01` `policy()`; `SP.05`.
  - AC: `min_notice_min` compared against `now`; `allowed: false` yields
    `{:policy, :cancellation | :reschedule, :not_allowed | :min_notice}`.
  - Tests: allowed/blocked/min-notice boundary.
- [x] M2.06 Benchmarks (`bench/run.exs`).
  - Spec: `SP.03` §10 complexity targets.
  - AC: subtraction over large busy sets and multi-week slot generation
    benchmarked; no quadratic scans.
  - Tests: `mix bench` runs; results in `bench/`.

## M3 — v0.3 Lifecycle, Events, Multi-party

> Specs: `SP.05`; `SP.03` §5; `SP.02`.
> Depends on: M2.
> Exit criteria: `:collective`/`:pool` modes; `Hold` + full intent/event
> emission; `reschedule/6` and `evaluate_cancellation/3` complete; a real
> consumer integration validates the boundary.

- [x] M3.01 `:collective` participant mode.
  - Spec: `SP.03` §5.
  - AC: slot offered only where ALL listed resources are free (free-time
    intersection before slotting).
  - Tests: example — one busy resource removes the shared slot.
- [x] M3.02 `:pool` participant mode (capacity-aware).
  - Spec: `SP.03` §5.
  - AC: slot offered while free resources ≥ `capacity_required`; `capacity > 1`
    counts remaining seats (capacity − overlapping bookings).
  - Tests: example — seat exhaustion; multi-capacity resource.
- [x] M3.03 `ExBooking.Hold` + `:reserve` / `:release` intents.
  - Spec: `SP.05`.
  - AC: holds are data (consumer-supplied id, `expires_at`); kernel expires
    nothing; holds appear as `kind: :hold` busy time.
  - Tests: hold as busy in a subsequent search; reserve precedes other intents.
- [x] M3.04 Full intent/event emission and ordering.
  - Spec: `SP.05` (canonical events + intent vocabulary).
  - AC: `Decision.events`/`intents` per spec; intents ordered persist-first
    (`:reserve` before `:calendar_event`/`:notify`/`:emit`); `routing_context`
    echoed into events untouched.
  - Tests: intent ordering; event `type` coverage.
- [x] M3.05 `ExBooking.reschedule/6`.
  - Spec: `SP.02`; `SP.05`.
  - AC: validates reschedule policy against `now` + existing slot; treats
    existing slot busy as released; emits `:booking_rescheduled` with old+new in
    `data`.
  - Tests: policy block; old slot released enables the new slot.
- [x] M3.06 `ExBooking.evaluate_cancellation/3`.
  - Spec: `SP.02`; `SP.05`.
  - AC: pure `{:ok, %{allowed?: _, reason: _}}` against `cancellation_policy`
    and `now`.
  - Tests: allowed/blocked/min-notice.
- [x] M3.07 Reference consumer integration validates the kernel boundary.
  - Spec: `R.01` §7; `SP.00` layering.
  - AC: an external consumer drives `available_slots/4` → `decide/5` and executes
    the returned intents; the boundary holds (no kernel changes needed).
  - Tests: documented integration walkthrough (out-of-repo consumer).

## M4 — v0.4 Standards Spike

> Specs: `SP.07` v0.4; `R.01` §3, §8.
> Depends on: M3. Dependency-heavy standards adapters are avoided unless the
> dependency discussion reopens them; built-in support remains narrow and
> explicit.

- [x] M4.01 RRULE expansion spike: evaluate `ical` vs `rrule` vs a minimal
  in-house RFC 5545 subset; keep any dep optional. (`cocktail` excluded on
  protocol alignment — `R.01` §4.)
- [x] M4.02 ICS free/busy import helpers (normalize into `Interval` lists).
- [x] M4.03 JSCalendar (RFC 8984) mapping scope for any JSON interop surface.
- [x] M4.04 Optional grid alignment to clock boundaries (`:align` option).

## M5 — v0.5 Research Audit Hardening

> Specs: `SP.02`; `SP.05`; `SP.07`.
> Depends on: M4.
> Exit criteria: important kernel-level gaps from the base research are closed,
> while orchestration-layer concerns stay outside the pure package.

- [x] M5.01 Rejected `decide/5` responses compute nearest alternatives when the
  caller supplies a `:from`/`:until` horizon.
  - Spec: `SP.02`; `SP.05`.
  - AC: alternatives sort by distance from requested start, then start time; no
    horizon means no guessed alternatives.
  - Tests: conflict decision with two nearest alternatives; no-horizon branch.
- [x] M5.02 Pure lifecycle transition helpers for cancellation, hold expiry, and
  no-show.
  - Spec: `SP.02`; `SP.05`.
  - AC: `cancel/3` validates policy and emits cancel intents; `expire_hold/2`
    emits release + expired event; `mark_no_show/3` emits no-show event.
  - Tests: allowed/blocked cancellation, hold expiry, no-show event.
- [x] M5.03 Preserve the kernel boundary after the research audit.
  - Spec: `SP.07`; `R.01`.
  - AC: payment state, provider behaviors, Ash wrappers, routing forms,
    analytics, GTM/CRM enrichment, and AI stay in consumers/adapters.
  - Tests: `mix check` green; docs explicitly record the boundary.

## Out of Scope, Permanently

Persistence, jobs, calendar/CRM/video/payment integrations, notifications, UI,
auth/tenancy, AI features, generic resource reservation, and GTM analytics. See
`SP.00` and `SP.07`.
