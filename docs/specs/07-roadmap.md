# Spec 07 — Roadmap

**Status:** informative

## v0.1 — temporal core (current)

- [x] Repo bootstrap, research doc, full spec, tooling, CI
- [x] `Interval` algebra: overlaps?/contains?/subtract/subtract_all/merge/clip/inflate
- [x] `Slotting.generate_slots/4` with independent slot interval
- [ ] Wall-time expansion with DST rules (`Schedule`)
- [ ] Availability assembly pipeline (`Availability`, `available_slots/4`)
- [ ] Conflict detection + `validate_request/5`
- [ ] Property/DST test corpus complete, ≥95% coverage held
- [ ] Re-enable dialyzer `extra_return` (drop `:no_extra_return` from mix.exs)
      once stubs are implemented

## v0.2 — assignment and policy

- [ ] All Spec 04 strategies + scoring hook
- [ ] `assign/3` public; `decide/5` for participants `:one`
- [ ] Policy evaluation: lead time, booking window, daily caps, cancellation/reschedule policies
- [ ] Benchmarks: subtraction over large busy sets, multi-week slot generation

## v0.3 — lifecycle, events, multi-party

- [ ] `:collective` and `:pool` participant modes
- [ ] `Hold`, full intent/event emission per Spec 05
- [ ] `reschedule/6`, `evaluate_cancellation/3` complete
- [ ] First consumer integration (host application) validates the boundary

## v0.4 — standards spike

- [ ] RRULE expansion: evaluate `cocktail` and `ical` vs minimal in-house
  RFC 5545 subset; pick one, keep the dep optional if possible
- [ ] ICS free/busy import helpers (normalization into `Interval` lists)
- [ ] Optional grid alignment to clock boundaries (`:align` option)

## Out of scope, permanently

Persistence, jobs, calendar/CRM/video/payment integrations, notifications, UI,
auth/tenancy, AI features, generic resource reservation (rooms/equipment/credits/
waitlists — LibreBooking territory), and GTM analytics. See Spec 00.

## Candidate future packages (not this repo)

- `booking_ash` — Ash resource/action wrapper around the kernel
- host apps/packs/plugins extension specs — tracked in their own repositories
