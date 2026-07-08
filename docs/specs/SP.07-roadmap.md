---
ex_booking:
  id: "SP.07"
  title: "Roadmap"
  domain: booking
  status: informative
  priority: medium
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["roadmap", "milestones", "standards-spike"]
  depends_on: ["R.01"]
---

# SP.07 — Roadmap

## v0.1 — temporal core

- [x] Repo bootstrap, research doc, full spec, tooling, CI
- [x] `Interval` algebra: overlaps?/contains?/subtract/subtract_all/merge/clip/inflate
- [x] `Slotting.generate_slots/4` with independent slot interval
- [x] Wall-time expansion with DST rules (`Schedule`)
- [x] Availability assembly pipeline (`Availability`, `available_slots/4`)
- [x] Conflict detection + `validate_request/5`
- [x] Property/DST test corpus complete, ≥95% coverage held
- [x] Re-enable dialyzer `extra_return` (drop `:no_extra_return` from mix.exs)
      once stubs are implemented

## v0.2 — assignment and policy

- [x] All SP.04 strategies + scoring hook
- [x] `assign/3` public; `decide/5` for participants `:one`
- [x] Policy evaluation: lead time, booking window, daily caps, cancellation/reschedule policies
- [x] Benchmarks: subtraction over large busy sets, multi-week slot generation

## v0.3 — lifecycle, events, multi-party

- [x] `:collective` and `:pool` participant modes
- [x] `Hold`, full intent/event emission per SP.05
- [x] `reschedule/6`, `evaluate_cancellation/3` complete
- [x] First real consumer integration validates the boundary

## v0.4 — standards spike (current)

- [x] RRULE expansion: evaluate `ical` (RFC 5545-compliant recurrence +
  parsing; enumerate its BY* coverage in the spike) and `rrule` (wraps the
  strictly validated `rust-rrule` crate; costs a Rust toolchain) vs a minimal
  in-house RFC 5545 subset; pick one, keep the dep optional if possible.
  `cocktail` is excluded on protocol alignment: its README documents
  unresolved DST bugs, incomplete RRULE options, and no WKST/EXRULE — DST
  correctness is this kernel's defining property (R.01 §4).
- [x] ICS free/busy import helpers (normalization into `Interval` lists)
- [x] JSCalendar (RFC 8984 / the 2.0 draft) mapping scope for any JSON
  interop surface — do not invent a JSON calendar shape
- [x] Optional grid alignment to clock boundaries (`:align` option)

## Out of scope, permanently

Persistence, jobs, calendar/CRM/video/payment integrations, notifications, UI,
auth/tenancy, AI features, generic resource reservation (rooms/equipment/credits/
waitlists — LibreBooking territory), and GTM analytics. See SP.00.

## Candidate future packages (not this repo)

- An Ash resource/action wrapper around the kernel
- Consumer-side extension specifications (orchestration, recipe bundles,
  vendor adapters) — tracked in their own repositories
